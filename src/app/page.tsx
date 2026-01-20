
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
import {
  SidebarProvider,
  Sidebar,
  SidebarHeader,
  SidebarContent,
  SidebarFooter,
  SidebarTrigger,
  SidebarInset,
} from '@/components/ui/sidebar';
import { Separator } from '@/components/ui/separator';


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
      if (groupName === 'README.md') {
        files.push({ repo: repoName, group: 'root', name: 'README.md', lang: 'markdown' });
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
        if (fileName.endsWith('.md')) lang = 'markdown';
        
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

    const groupOrder = ['root', 'manifests', 'templates', 'files', 'scripts'];
    return Object.entries(filesByGroup).sort(
        ([a], [b]) => groupOrder.indexOf(a) - groupOrder.indexOf(b)
    );
};


export default function Home() {
  const [selectedRepo, setSelectedRepo] = useState<string>(REPO_NAMES[0]);
   const [selectedFile, setSelectedFile] = useState<PuppetFile | null>(
    allPuppetFiles.find(f => f.repo === selectedRepo && f.name === 'init.pp' && f.group === 'manifests')!
  );
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownload = async () => {
    setIsDownloading(true);
    const zip = new JSZip();

    Object.entries(puppetCode).forEach(([repoName, repoData]) => {
      const repoFolder = zip.folder(repoName);
      if (!repoFolder) return;

      Object.entries(repoData).forEach(([groupOrFileName, content]) => {
        if (groupOrFileName === 'metadata.json' || groupOrFileName === 'README.md') {
          repoFolder.file(groupOrFileName, content as string);
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
    const firstFile = allPuppetFiles.find(f => f.repo === repoName && f.name === 'init.pp' && f.group === 'manifests');
    if(firstFile) {
        setSelectedFile(firstFile);
    } else {
        setSelectedFile(allPuppetFiles.find(f => f.repo === repoName) ?? null);
    }
  };

  const sortedGroups = getRepoFilesByGroup(selectedRepo);

  return (
    <SidebarProvider>
      <Sidebar className="border-r bg-card text-card-foreground">
        <SidebarHeader className="p-2">
            <div className="flex items-center gap-3">
             <div className="bg-primary text-primary-foreground p-2 rounded-lg shadow-md">
                <RocketIcon className="w-6 h-6" />
             </div>
             <h2 className="text-xl font-semibold text-primary">Cassandra Deployer</h2>
          </div>
        </SidebarHeader>
        <Separator />
        <SidebarContent className="p-0">
            <div className="p-4">
                 <Select value={selectedRepo} onValueChange={handleRepoChange}>
                  <SelectTrigger className="w-full">
                    <SelectValue placeholder="Select a repository" />
                  </SelectTrigger>
                  <SelectContent>
                    {REPO_NAMES.map(repo => (
                      <SelectItem key={repo} value={repo}>
                        <div className="flex items-center gap-2">
                           <Package className="h-4 w-4" /> 
                           <span>{repo}</span>
                        </div>
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
            </div>
             <Accordion
              type="multiple"
              defaultValue={['root', 'manifests', 'templates', 'files']}
              className="w-full px-4"
            >
              {sortedGroups.map(([group, files]) => (
                <AccordionItem value={group} key={group} className="border-b-0">
                  <AccordionTrigger className="px-2 py-1.5 text-sm hover:bg-muted rounded-md hover:no-underline">
                    <div className="flex items-center gap-2">
                      <Folder className="h-5 w-5 text-primary" />
                      <span className="font-semibold">{group}</span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pl-4">
                    <div className="flex flex-col gap-1 mt-1">
                      {files.map((file) => (
                        <Button
                          key={`${file.group}-${file.name}`}
                          variant="ghost"
                          size="sm"
                          className={cn(
                            'justify-start gap-2 h-8 font-normal',
                            selectedFile?.name === file.name && selectedFile?.group === file.group &&
                              'bg-accent text-accent-foreground hover:bg-accent/90 hover:text-accent-foreground'
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
        </SidebarContent>
        <SidebarFooter className="p-4 border-t">
             <Button onClick={handleDownload} disabled={isDownloading} className="w-full">
                <Download className="mr-2 h-4 w-4" />
                {isDownloading ? 'Downloading...' : `Download All Modules`}
              </Button>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset>
        <main className="min-h-screen bg-background font-body text-foreground">
            <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b bg-background/95 backdrop-blur-sm px-4 lg:h-[60px] lg:px-6">
                <SidebarTrigger className="md:hidden" />
                <div className="flex-1">
                     {selectedFile && (
                        <span className="font-mono text-sm bg-muted px-2 py-1 rounded">
                            {selectedFile.repo}/{selectedFile.group === 'root'
                            ? selectedFile.name
                            : `${selectedFile.group}/${selectedFile.name}`}
                        </span>
                     )}
                </div>
            </header>

            <div className="flex-1 p-4 md:p-6 lg:p-8">
                {selectedFile ? (
                    <Card className="w-full shadow-md border">
                        <CardHeader>
                            <CardTitle>{selectedFile.name}</CardTitle>
                        </CardHeader>
                        <CardContent>
                            {selectedFile.name === 'init.pp' && selectedFile.repo === 'cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
                                <Terminal className="h-4 w-4 text-accent" />
                                <AlertTitle>Component Module</AlertTitle>
                                <AlertDescription>
                                This is the main component module. It is highly parameterized and should not contain direct Hiera lookups.
                                </AlertDescription>
                            </Alert>
                            )}
                            {selectedFile.name === 'init.pp' && selectedFile.repo === 'profile_cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
                                <Terminal className="h-4 w-4 text-accent" />
                                <AlertTitle>Profile Module</AlertTitle>
                                <AlertDescription>
                                This profile wraps the component module and provides its data via Hiera.
                                </AlertDescription>
                            </Alert>
                            )}
                            {selectedFile.name === 'init.pp' && selectedFile.repo === 'role_cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
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
                                ? (puppetCode as any)[selectedFile.repo][selectedFile.name]
                                : (puppetCode as any)[selectedFile.repo]?.[selectedFile.group]?.[selectedFile.name] ?? `// ${selectedFile.name} is not available in the preview.`
                            }
                            />
                        </CardContent>
                    </Card>
                ) : (
                    <div className="flex flex-col items-center justify-center h-[60vh] text-center text-muted-foreground rounded-lg border-2 border-dashed">
                        <Package className="mx-auto h-16 w-16" />
                        <h2 className="mt-4 text-xl font-semibold">Welcome to the Cassandra Deployer</h2>
                        <p className="mt-2 max-w-md">Select a file from the sidebar to explore the Puppet modules that power your Cassandra deployment architecture.</p>
                    </div>
                )}
            </div>
            <footer className="text-center p-4 text-sm text-muted-foreground">
                <p>Built for stability and scale.</p>
            </footer>
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}
