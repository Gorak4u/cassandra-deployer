'use server';

import path from 'path';
import fs from 'fs/promises';
import { glob } from 'glob';
import archiver from 'archiver';
import { Readable } from 'stream';
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
    if (fileName.endsWith('.pp')) return 'puppet';
    if (fileName.endsWith('.erb') || fileName.endsWith('.epp')) return 'ruby';
    if (fileName.endsWith('.yaml')) return 'yaml';
    if (fileName.endsWith('.sh')) return 'bash';
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
    let name = parts[parts.length - 1];

    if (parts.length > 2) {
      group = parts[1];
      name = parts.slice(2).join(path.sep);
    } else {
      name = parts[1];
    }
    
    if (parts.length === 2) {
        group = 'root';
        name = parts[1];
    } else if (parts.length > 2) {
        group = parts[1];
        name = parts.slice(2).join(path.sep);
    }


    return {
      repo,
      group,
      name: parts.slice(1).join('/'),
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
        let node = currentLevel.find(n => n.name === part);

        if (!node) {
            node = { name: part, path: file.path.split(path.sep).slice(0, index + 2).join(path.sep) };
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

    archive.directory(puppetDir, false);
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
