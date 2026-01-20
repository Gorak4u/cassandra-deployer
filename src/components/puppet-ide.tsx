
'use client';

import { useState } from 'react';
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
  SidebarInset,
  SidebarTrigger,
} from '@/components/ui/sidebar';
import { Separator } from '@/components/ui/separator';
import type { PuppetFile } from '@/lib/actions';
import { getFileContent, getZippedModules } from '@/lib/actions';
import { MarkdownView } from './markdown-view';


const getRepoFilesByGroup = (repoName: string, allFiles: PuppetFile[]) => {
    const repoFiles = allFiles.filter(f => f.repo === repoName);
    const filesByGroup = repoFiles.reduce((acc, file) => {
        const group = file.path.split('/')[1] ?? 'root';
        if (!acc[group]) {
            acc[group] = [];
        }
        acc[group].push(file);
        return acc;
    }, {} as Record<string, PuppetFile[]>);
    
    // Sort files within each group
    for (const group in filesByGroup) {
        filesByGroup[group].sort((a, b) => a.name.localeCompare(b.name));
    }

    const groupOrder = ['root', 'manifests', 'templates', 'files', 'tasks', 'readme'];
    return Object.entries(filesByGroup).sort(
        ([a], [b]) => {
            const indexA = groupOrder.indexOf(a);
            const indexB = groupOrder.indexOf(b);
            if (indexA === -1) return 1;
            if (indexB === -1) return -1;
            return indexA - indexB;
        }
    );
};

export function PuppetIDE({ allFiles, repoNames }: { allFiles: PuppetFile[], repoNames: string[]}) {
  const [selectedRepo, setSelectedRepo] = useState<string>(repoNames[0]);
  const [selectedFile, setSelectedFile] = useState<PuppetFile | null>(null);
  const [fileContent, setFileContent] = useState('// Select a file to view its content');
  const [isDownloading, setIsDownloading] = useState(false);
  const [isLoadingFile, setIsLoadingFile] = useState(false);

  const handleFileSelect = async (file: PuppetFile) => {
    setSelectedFile(file);
    setIsLoadingFile(true);
    try {
      const content = await getFileContent(file.path);
      setFileContent(content);
    } catch (e) {
      setFileContent('// Error loading file');
    } finally {
      setIsLoadingFile(false);
    }
  };
  
  const handleDownload = async () => {
    setIsDownloading(true);
    try {
      const base64 = await getZippedModules();
      const blob = await (await fetch(`data:application/zip;base64,${base64}`)).blob();
      saveAs(blob, `puppet-cassandra-modules.zip`);
    } catch (error) {
      console.error('Error creating zip file:', error);
    } finally {
      setIsDownloading(false);
    }
  };

  const handleRepoChange = (repoName: string) => {
    setSelectedRepo(repoName);
    const firstFile = allFiles.find(f => f.repo === repoName && f.name.endsWith('init.pp'));
    if(firstFile) {
        handleFileSelect(firstFile);
    } else {
        setSelectedFile(null);
        setFileContent('// Select a file to view its content');
    }
  };

  const sortedGroups = getRepoFilesByGroup(selectedRepo, allFiles);

  return (
    <SidebarProvider>
      <Sidebar className="border-r bg-sidebar text-sidebar-foreground">
        <SidebarHeader className="p-2">
            <div className="flex items-center gap-3">
             <div className="bg-primary text-primary-foreground p-2 rounded-lg shadow-md">
                <RocketIcon className="w-6 h-6" />
             </div>
             <h2 className="text-xl font-semibold text-sidebar-primary">Cassandra Deployer</h2>
          </div>
        </SidebarHeader>
        <Separator />
        <SidebarContent className="p-0">
            <div className="p-4">
                 <Select value={selectedRepo} onValueChange={handleRepoChange}>
                  <SelectTrigger className="w-full bg-sidebar-background border-sidebar-border focus:ring-sidebar-ring">
                    <SelectValue placeholder="Select a repository" />
                  </SelectTrigger>
                  <SelectContent>
                    {repoNames.map(repo => (
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
                  <AccordionTrigger className="px-2 py-1.5 text-sm hover:bg-sidebar-accent/80 rounded-md hover:no-underline capitalize">
                    <div className="flex items-center gap-2">
                      <Folder className="h-5 w-5 text-sidebar-primary" />
                      <span className="font-semibold">{group === 'root' ? 'Module Root' : group}</span>
                    </div>
                  </AccordionTrigger>
                  <AccordionContent className="pl-4">
                    <div className="flex flex-col gap-1 mt-1">
                      {files.map((file) => (
                        <Button
                          key={file.path}
                          variant="ghost"
                          size="sm"
                          className={cn(
                            'justify-start gap-2 h-8 font-normal text-sidebar-foreground/80 hover:bg-sidebar-accent/70 hover:text-sidebar-accent-foreground',
                            selectedFile?.path === file.path &&
                              'bg-sidebar-accent text-sidebar-accent-foreground hover:bg-sidebar-accent/90 hover:text-sidebar-accent-foreground'
                          )}
                          onClick={() => handleFileSelect(file)}
                        >
                          <FileIcon className="h-4 w-4" />
                          {file.name.split('/').pop()}
                        </Button>
                      ))}
                    </div>
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
        </SidebarContent>
        <SidebarFooter className="p-4 border-t border-sidebar-border">
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
                            {selectedFile.path}
                        </span>
                     )}
                </div>
            </header>

            <div className="flex-1 p-4 md:p-6 lg:p-8">
                {selectedFile ? (
                    <Card className="w-full shadow-md border">
                        <CardHeader>
                            <CardTitle>{selectedFile.name.split('/').pop()}</CardTitle>
                        </CardHeader>
                        <CardContent>
                            {selectedFile.name.endsWith('init.pp') && selectedFile.repo === 'cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
                                <Terminal className="h-4 w-4 text-accent" />
                                <AlertTitle>Component Module</AlertTitle>
                                <AlertDescription>
                                This is the main component module. It is highly parameterized and should not contain direct Hiera lookups.
                                </AlertDescription>
                            </Alert>
                            )}
                            {selectedFile.name.endsWith('init.pp') && selectedFile.repo === 'profile_cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
                                <Terminal className="h-4 w-4 text-accent" />
                                <AlertTitle>Profile Module</AlertTitle>
                                <AlertDescription>
                                This profile wraps the component module and provides its data via Hiera.
                                </AlertDescription>
                            </Alert>
                            )}
                            {selectedFile.name.endsWith('init.pp') && selectedFile.repo === 'role_cassandra_pfpt' && (
                            <Alert className="mb-6 border-accent text-accent-foreground bg-accent/10">
                                <Terminal className="h-4 w-4 text-accent" />
                                <AlertTitle>Role Module</AlertTitle>
                                <AlertDescription>
                                This role includes the profile to define a complete Cassandra server. This is what you assign to nodes.
                                </AlertDescription>
                            </Alert>
                            )}
                            {selectedFile.lang === 'markdown' ? (
                                <div className="p-4 bg-background rounded-md overflow-x-auto">
                                  <MarkdownView content={isLoadingFile ? 'Loading...' : fileContent} />
                                </div>
                              ) : (
                                <CodeBlock
                                  code={isLoadingFile ? '// Loading...' : fileContent}
                                  language={selectedFile.lang}
                                />
                              )}
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
