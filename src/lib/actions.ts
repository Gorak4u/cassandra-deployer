'use server';

import path from 'path';
import fs from 'fs/promises';
import { glob } from 'glob';
import archiver from 'archiver';
import { Readable } from 'stream';
import git from 'isomorphic-git';
import http from 'isomorphic-git/http/node';
import { validateCode } from '@/ai/flows/validate-code-flow';
import type { ValidateCodeOutput } from '@/ai/flows/validate-code-flow';

const puppetDir = path.join(process.cwd(), 'src', 'puppet');

export type PuppetFile = {
  repo: string;
  group: string;
  name: string;
  path: string; // Relative path from src/puppet
  lang: string;
};

export type FileTreeNode = {
    name: string;
    path: string;
    children?: FileTreeNode[];
    file?: PuppetFile;
}


const getLang = (fileName: string) => {
    if (fileName.endsWith('.pp') || fileName.endsWith('.pp.txt')) return 'puppet';
    if (fileName.endsWith('.erb') || fileName.endsWith('.epp') || fileName.endsWith('.erb.txt')) return 'ruby';
    if (fileName.endsWith('.yaml')) return 'yaml';
    if (fileName.endsWith('.sh') || fileName.endsWith('cass-ops.txt')) return 'bash';
    if (fileName.endsWith('.py')) return 'python';
    if (fileName.endsWith('.jar')) return 'binary';
    if (fileName.endsWith('.md')) return 'markdown';
    if (fileName.endsWith('.json')) return 'json';
    return 'text';
}

export async function getPuppetFileTree(): Promise<{tree: Record<string, FileTreeNode[]>, allFiles: PuppetFile[]}> {
  const files = await glob('**/*', { cwd: puppetDir, nodir: true });
  
  const allPuppetFiles: PuppetFile[] = files.map(file => {
    const parts = file.split(path.sep);
    const repo = parts[0];
    let group = 'root';
    if (parts.length > 2) {
      group = parts[1];
    }
    
    const relativePath = parts.slice(1).join('/');
    const displayName = relativePath
      .replace(/\.pp\.txt$/, '.pp')
      .replace(/\.erb\.txt$/, '.erb')
      .replace(/cass-ops\.txt$/, 'cass-ops');

    return {
      repo,
      group,
      name: displayName,
      path: file,
      lang: getLang(parts[parts.length - 1]),
    };
  });

  const tree: Record<string, FileTreeNode[]> = {};
  allPuppetFiles.forEach(file => {
    if (!tree[file.repo]) {
        tree[file.repo] = [];
    }

    const pathParts = file.path.split(path.sep).slice(1); // remove repo name
    let currentLevel = tree[file.repo];

    pathParts.forEach((part, index) => {
        let node = currentLevel.find(n => n.name === part.replace(/\.pp\.txt$/, '.pp').replace(/\.erb\.txt$/, '.erb').replace(/cass-ops\.txt$/, 'cass-ops'));

        if (!node) {
            const nodeName = part.replace(/\.pp\.txt$/, '.pp').replace(/\.erb\.txt$/, '.erb').replace(/cass-ops\.txt$/, 'cass-ops');
            node = { name: nodeName, path: file.path.split(path.sep).slice(0, index + 2).join(path.sep) };
            currentLevel.push(node);
        }
        
        if (index === pathParts.length - 1) {
            node.file = file;
        } else {
            if (!node.children) {
                node.children = [];
            }
            currentLevel = node.children;
        }
    });

  });

  return { tree, allFiles: allPuppetFiles };
}

export async function getFileContent(filePath: string): Promise<string> {
  try {
    const fullPath = path.join(puppetDir, filePath);
    // Security check to prevent directory traversal
    if (!fullPath.startsWith(puppetDir)) {
      throw new Error('Access denied');
    }
    const content = await fs.readFile(fullPath, 'utf-8');
    return content;
  } catch (error) {
    console.error(`Error reading file ${filePath}:`, error);
    return `// Error: Could not load file content for ${filePath}`;
  }
}

export async function getZippedModules(): Promise<string> {
    const archive = archiver('zip', {
        zlib: { level: 9 } 
    });

    const streamToBuffer = (stream: NodeJS.ReadableStream): Promise<Buffer> => {
        return new Promise((resolve, reject) => {
            const chunks: Buffer[] = [];
            stream.on('data', chunk => chunks.push(chunk));
            stream.on('error', reject);
            stream.on('end', () => resolve(Buffer.concat(chunks)));
        });
    };
    
    const files = await glob('**/*', { cwd: puppetDir, nodir: true, dot: true });

    for (const file of files) {
        const filePath = path.join(puppetDir, file);
        const stat = await fs.lstat(filePath);
        if (stat.isFile()) {
            const fileContent = await fs.readFile(filePath);
            
            let zipPath = file;
            if (file.endsWith('.pp.txt')) {
                zipPath = file.replace(/\.pp\.txt$/, '.pp');
            } else if (file.endsWith('.erb.txt')) {
                zipPath = file.replace(/\.erb\.txt$/, '.erb');
            } else if (file.endsWith('cass-ops.txt')) {
                zipPath = file.replace(/\.txt$/, '');
            }
            
            archive.append(fileContent, { name: zipPath });
        }
    }

    await archive.finalize();

    const buffer = await streamToBuffer(archive);
    return buffer.toString('base64');
}

export async function validateCodeAction(code: string, language: string): Promise<ValidateCodeOutput> {
  // Do not validate binary files or very large files to save costs
  if (language === 'binary' || code.length > 20000) {
    return { isValid: true, issues: [] };
  }
  try {
    return await validateCode({ code, language });
  } catch (error) {
    console.error('Error validating code with Genkit flow:', error);
    // Return a structured error that the client can display
    return {
      isValid: false,
      issues: [
        'The AI validator failed to process the request. This may be due to an API error or content safety restrictions.',
      ],
    };
  }
}

export async function pushToGit(data: {
  repoUrl: string;
  pat: string;
}): Promise<{ success: boolean; message: string }> {
  const tempRepoDir = path.join('/tmp', `puppet-repo-${Date.now()}`);

  try {
    // 1. Initialize a temporary git repository
    await fs.mkdir(tempRepoDir, { recursive: true });
    await git.init({ fs, dir: tempRepoDir });

    // 2. Copy module files to the temporary repository
    const puppetModulesDir = path.join(process.cwd(), 'src', 'puppet');
    const allFiles = await glob('**/*', { cwd: puppetModulesDir, nodir: true, dot: true });

    for (const file of allFiles) {
      const srcPath = path.join(puppetModulesDir, file);
      
      let destFile = file;
      if (file.endsWith('.pp.txt')) {
          destFile = file.replace(/\.pp\.txt$/, '.pp');
      } else if (file.endsWith('.erb.txt')) {
          destFile = file.replace(/\.erb\.txt$/, '.erb');
      } else if (file.endsWith('cass-ops.txt')) {
        destFile = file.replace(/\.txt$/, '');
      }

      const destPath = path.join(tempRepoDir, destFile);
      await fs.mkdir(path.dirname(destPath), { recursive: true });
      await fs.copyFile(srcPath, destPath);
    }
    
    // 3. Add all files and commit
    await git.add({ fs, dir: tempRepoDir, filepath: '.' });
    
    await git.commit({
      fs,
      dir: tempRepoDir,
      author: {
        name: 'Firebase Studio',
        email: 'studio-bot@example.com',
      },
      message: 'Deploy Puppet modules from Firebase Studio',
    });
    
    // 4. Add remote and push
    await git.addRemote({
      fs,
      dir: tempRepoDir,
      remote: 'origin',
      url: data.repoUrl,
    });

    const result = await git.push({
      fs,
      http,
      dir: tempRepoDir,
      remote: 'origin',
      ref: 'HEAD',
      remoteRef: 'refs/heads/main',
      force: true, // Force push to overwrite history, simpler for this use case
      onAuth: () => ({
        username: data.pat,
      }),
    });

    if (result.ok) {
      return { success: true, message: `Pushed successfully!` };
    } else {
      const errorMessage = result.errors?.join(' ') || 'Unknown push error.';
      console.error('Git push failed:', result.errors);
      return { success: false, message: `Git push failed: ${errorMessage}` };
    }
  } catch (error: any) {
    console.error('An error occurred during git push:', error);
    return { success: false, message: error.message || 'An unexpected error occurred.' };
  } finally {
    // 5. Clean up the temporary directory
    await fs.rm(tempRepoDir, { recursive: true, force: true });
  }
}
