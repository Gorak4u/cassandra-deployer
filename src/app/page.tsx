
'use client';

import { useState } from 'react';
import JSZip from 'jszip';
import { saveAs } from 'file-saver';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from '@/components/ui/accordion';
import { RocketIcon } from '@/components/icons';
import { CodeBlock } from '@/components/code-block';
import { puppetCode } from '@/lib/puppet-code';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Terminal, Folder, File as FileIcon, Download, Package } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';


type PuppetFile = {
  repo: string;
  group: string;
  name: string;
  lang: string;
};

const getPuppetFiles = (): PuppetFile[] => {
  const files: PuppetFile[] = [];
  for (const repoName in puppetCode) {
    const repo = (puppetCode as any)[repoName];
    for (const groupName in repo) {
      if (groupName === 'metadata.json') {
        files.push({ repo: repoName, group: 'root', name: 'metadata.json', lang: 'json' });
        continue;
      }
      const group = repo[groupName];
      for (const fileName in group) {
        let lang = 'text';
        if (fileName.endsWith('.pp')) lang = 'puppet';
        if (fileName.endsWith('.erb') || fileName.endsWith('.epp')) lang = 'ruby';
        if (fileName.endsWith('.yaml')) lang = 'yaml';
        if (fileName.endsWith('.sh')) lang = 'bash';
        if (fileName.endsWith('.py')) lang = 'python';
        if (fileName.endsWith('.jar')) lang = 'binary';
        
        files.push({ repo: repoName, group: groupName, name: fileName, lang });
      }
    }
  }
  return files;
};

const allPuppetFiles = getPuppetFiles();

const REPO_NAMES = Object.keys(puppetCode);

const getRepoFilesByGroup = (repoName: string) => {
    const repoFiles = allPuppetFiles.filter(f => f.repo === repoName);
    const filesByGroup = repoFiles.reduce((acc, file) => {
        if (!acc[file.group]) {
            acc[file.group] = [];
        }
        acc[file.group].push(file);
        return acc;
    }, {} as Record<string, PuppetFile[]>);

    const groupOrder = ['root', 'manifests', 'templates', 'scripts', 'files'];
    return Object.entries(filesByGroup).sort(
        ([a], [b]) => groupOrder.indexOf(a) - groupOrder.indexOf(b)
    );
};


export default function Home() {
  const [selectedRepo, setSelectedRepo] = useState<string>(REPO_NAMES[0]);
  const [selectedFile, setSelectedFile] = useState<PuppetFile>(
    allPuppetFiles.find(f => f.repo === selectedRepo && f.name === 'init.pp')!
  );
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownload = async () => {
    setIsDownloading(true);
    const zip = new JSZip();

    Object.entries(puppetCode).forEach(([repoName, repoData]) => {
      const repoFolder = zip.folder(repoName);
      if (!repoFolder) return;

      Object.entries(repoData).forEach(([groupOrFileName, content]) => {
        if (groupOrFileName === 'metadata.json') {
          repoFolder.file('metadata.json', content as string);
        } else if (typeof content === 'object' && content !== null) {
          const groupFolder = repoFolder.folder(groupOrFileName);
          if (groupFolder) {
            Object.entries(content).forEach(([fileName, fileContent]) => {
               if (fileContent === null) return;
               if (fileName.endsWith('.jar')) {
                 groupFolder.file(fileName, 'binary content placeholder', { binary: true });
               } else {
                 groupFolder.file(fileName, fileContent as string);
               }
            });
          }
        }
      });
    });
    
    try {
      const content = await zip.generateAsync({ type: 'blob' });
      saveAs(content, `puppet-cassandra-modules.zip`);
    } catch (error) {
      console.error('Error creating zip file:', error);
    } finally {
      setIsDownloading(false);
    }
  };

  const handleRepoChange = (repoName: string) => {
    setSelectedRepo(repoName);
    const firstFile = allPuppetFiles.find(f => f.repo === repoName);
    if(firstFile) {
        setSelectedFile(firstFile);
    }
  };

  const sortedGroups = getRepoFilesByGroup(selectedRepo);

  return (
    <main className="min-h-screen bg-background font-body text-foreground">
      <div className="container mx-auto p-4 md:p-8">
        <header className="flex items-center justify-between gap-4 mb-8">
          <div className="flex items-center gap-4">
            <div className="bg-primary text-primary-foreground p-3 rounded-lg shadow-md">
              <RocketIcon className="w-8 h-8" />
            </div>
            <div>
              <h1 className="text-3xl md:text-4xl font-headline font-bold text-primary">
                Cassandra Deployer
              </h1>
              <p className="text-muted-foreground mt-1">
                Generate a modern Puppet architecture for deploying Apache Cassandra.
              </p>
            </div>
          </div>
          <Button onClick={handleDownload} disabled={isDownloading}>
            <Download className="mr-2 h-4 w-4" />
            {isDownloading ? 'Downloading...' : `Download All Modules`}
          </Button>
        </header>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-1">
            <Card className="shadow-lg sticky top-8">
              <CardHeader>
                <CardTitle>Puppet Repositories</CardTitle>
                 <Select value={selectedRepo} onValueChange={handleRepoChange}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Select a repository" />
                  </SelectTrigger>
                  <SelectContent>
                    {REPO_NAMES.map(repo => (
                      <SelectItem key={repo} value={repo}>
                        <div className="flex items-center gap-2">
                           <Package className="h-4 w-4" /> 
                           {repo}
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </CardHeader>
              <CardContent>
                <Accordion
                  type="multiple"
                  defaultValue={['root', 'manifests', 'templates', 'scripts', 'files']}
                  className="w-full"
                >
                  {sortedGroups.map(([group, files]) => (
                    <AccordionItem value={group} key={group}>
                      <AccordionTrigger>
                        <div className="flex items-center gap-2">
                          <Folder className="h-5 w-5 text-primary" />
                          <span className="font-semibold">{group}</span>
                        </div>
                      </AccordionTrigger>
                      <AccordionContent>
                        <div className="flex flex-col gap-1 pl-4">
                          {files.map((file) => (
                            <Button
                              key={file.name}
                              variant="ghost"
                              className={cn(
                                'justify-start gap-2',
                                selectedFile?.name === file.name && selectedFile?.group === file.group &&
                                  'bg-accent text-accent-foreground'
                              )}
                              onClick={() => setSelectedFile(file)}
                            >
                              <FileIcon className="h-4 w-4" />
                              {file.name}
                            </Button>
                          ))}
                        </div>
                      </AccordionContent>
                    </AccordionItem>
                  ))}
                </Accordion>
              </CardContent>
            </Card>
          </div>
          <div className="lg:col-span-2">
           {selectedFile && (
            <Card className="w-full shadow-lg">
              <CardHeader>
                <CardTitle>{selectedFile.name}</CardTitle>
                <CardDescription>
                  <span className="font-mono text-sm bg-muted px-1 py-0.5 rounded">
                    {selectedFile.repo}/{selectedFile.group === 'root'
                      ? selectedFile.name
                      : `${selectedFile.group}/${selectedFile.name}`}
                  </span>
                </CardDescription>
              </CardHeader>
              <CardContent>
                {selectedFile.name === 'init.pp' && selectedFile.repo === 'cassandra_pfpt' && (
                  <Alert className="mb-6 border-accent">
                    <Terminal className="h-4 w-4 text-accent" />
                    <AlertTitle>Component Module</AlertTitle>
                    <AlertDescription>
                      This is the main component module. It is highly parameterized and should not contain direct Hiera lookups.
                    </AlertDescription>
                  </Alert>
                )}
                 {selectedFile.name === 'init.pp' && selectedFile.repo === 'profile_cassandra_pfpt' && (
                  <Alert className="mb-6 border-accent">
                    <Terminal className="h-4 w-4 text-accent" />
                    <AlertTitle>Profile Module</AlertTitle>
                    <AlertDescription>
                      This profile wraps the component module and provides its data via Hiera.
                    </AlertDescription>
                  </Alert>
                )}
                 {selectedFile.name === 'init.pp' && selectedFile.repo === 'role_cassandra_pfpt' && (
                  <Alert className="mb-6 border-accent">
                    <Terminal className="h-4 w-4 text-accent" />
                    <AlertTitle>Role Module</AlertTitle>
                    <AlertDescription>
                      This role includes the profile to define a complete Cassandra server. This is what you assign to nodes.
                    </AlertDescription>
                  </Alert>
                )}
                <CodeBlock
                  code={
                    selectedFile.group === 'root'
                    ? (puppetCode as any)[selectedFile.repo]['metadata.json']
                    : (puppetCode as any)[selectedFile.repo]?.[selectedFile.group]?.[selectedFile.name] ?? `// ${selectedFile.name} is not available in the preview.`
                  }
                />
              </CardContent>
            </Card>
           )}
          </div>
        </div>

        <footer className="text-center mt-8 text-sm text-muted-foreground">
          <p>Built for stability and scale.</p>
        </footer>
      </div>
    </main>
  );
}
