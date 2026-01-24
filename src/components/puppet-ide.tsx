
'use client';

import { useState } from 'react';
import { saveAs } from 'file-saver';
import {
  Card,
  CardContent,
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
import { 
    Terminal, 
    Folder, 
    File as FileIcon, 
    Download, 
    Package,
    Puzzle,
    FileCode,
    FileJson,
    Shell,
    FileText,
    FileCog,
    ShieldCheck,
    AlertTriangle,
    CheckCircle,
    Info,
    Github,
} from 'lucide-react';
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
import { getFileContent, getZippedModules, validateCodeAction } from '@/lib/actions';
import type { ValidateCodeOutput } from '@/ai/flows/validate-code-flow';
import { MarkdownView } from './markdown-view';
import { Skeleton } from './ui/skeleton';
import { GitPushDialog } from './git-push-dialog';


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
  const [isValidating, setIsValidating] = useState(false);
  const [validationResult, setValidationResult] = useState<ValidateCodeOutput | null>(null);
  const [isGitPushDialogOpen, setIsGitPushDialogOpen] = useState(false);

  const getFileIcon = (lang: string) => {
    switch (lang) {
        case 'puppet':
            return <Puzzle className="h-4 w-4" />;
        case 'ruby':
            return <FileCode className="h-4 w-4" />;
        case 'yaml':
        case 'json':
            return <FileJson className="h-4 w-4" />;
        case 'bash':
            return <Shell className="h-4 w-4" />;
        case 'markdown':
            return <FileText className="h-4 w-4" />;
        case 'binary':
            return <FileCog className="h-4 w-4" />;
        default:
            return <FileIcon className="h-4 w-4" />;
    }
  }

  const handleFileSelect = async (file: PuppetFile) => {
    setSelectedFile(file);
    setIsLoadingFile(true);
    setValidationResult(null);
    try {
      const content = await getFileContent(file.path);
      setFileContent(content);
    } catch (e) {
      setFileContent('// Error loading file');
    } finally {
      setIsLoadingFile(false);
    }
  };

  const handleValidate = async () => {
    if (!selectedFile || !fileContent) return;
    setIsValidating(true);
    setValidationResult(null);
    try {
      const result = await validateCodeAction(fileContent, selectedFile.lang);
      setValidationResult(result);
    } catch (error) {
      console.error('Validation failed', error);
      setValidationResult({ isValid: false, issues: ['An unexpected error occurred during validation.'] });
    } finally {
      setIsValidating(false);
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
    setValidationResult(null);
    const firstFile = allFiles.find(f => f.repo === repoName && (f.name.endsWith('init.pp') || f.name.endsWith('init.pp.txt')));
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
                          {getFileIcon(file.lang)}
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
      <GitPushDialog isOpen={isGitPushDialogOpen} onOpenChange={setIsGitPushDialogOpen} />
      <SidebarInset>
        <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b bg-background/95 backdrop-blur-sm px-4 lg:h-[60px] lg:px-6">
            <SidebarTrigger className="md:hidden" />
            <div className="flex-1">
                 {selectedFile && (
                    <span className="font-mono text-sm bg-muted px-2 py-1 rounded">
                        {selectedFile.path.replace(/\.pp\.txt$/, '.pp').replace(/\.erb\.txt$/, '.erb')}
                    </span>
                 )}
            </div>
            <Button variant="outline" size="sm" onClick={() => setIsGitPushDialogOpen(true)}>
                <Github className="mr-2 h-4 w-4" />
                Push to Git
            </Button>
            {selectedFile && selectedFile.lang !== 'binary' && (
              <Button variant="outline" size="sm" onClick={handleValidate} disabled={isValidating}>
                {isValidating ? (
                  <><FileCog className="mr-2 h-4 w-4 animate-spin" /> Validating...</>
                ) : (
                  <><ShieldCheck className="mr-2 h-4 w-4" /> Validate File</>
                )}
              </Button>
            )}
        </header>

        <div className="flex-1 overflow-y-auto p-4 md:p-6 lg:p-8">
            {selectedFile && selectedFile.lang !== 'binary' && (
              <Alert className="mb-6 border-blue-500/50 bg-blue-50 text-blue-900 dark:bg-blue-950 dark:text-blue-300 dark:border-blue-900 [&>svg]:text-blue-500">
                  <Info className="h-4 w-4" />
                  <AlertTitle>Note on AI Usage</AlertTitle>
                  <AlertDescription>
                  The "Validate File" feature uses an AI model. Please be aware that running this feature may incur costs from your cloud provider.
                  </AlertDescription>
              </Alert>
            )}
            {validationResult && (
              <Alert variant={validationResult.isValid ? 'default' : 'destructive'} className={cn("mb-6", validationResult.isValid && "border-green-500/50 bg-green-50 text-green-900 [&>svg]:text-green-500 dark:bg-green-950 dark:text-green-300 dark:border-green-900")}>
                {validationResult.isValid ? <CheckCircle className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
                <AlertTitle>{validationResult.isValid ? 'Validation Successful' : 'Validation Failed'}</AlertTitle>
                <AlertDescription>
                  {validationResult.isValid ? 'The AI validator found no critical issues in the code.' : (
                    <ul className="list-disc pl-5 mt-2 space-y-1">
                      {validationResult.issues.map((issue, i) => <li key={i}>{issue}</li>)}
                    </ul>
                  )}
                </AlertDescription>
              </Alert>
            )}
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
                        {isLoadingFile ? (
                            <Skeleton className="h-96 w-full rounded-md" />
                        ) : selectedFile.lang === 'markdown' ? (
                            <div className="p-4 bg-background rounded-md overflow-x-auto">
                              <MarkdownView content={fileContent} />
                            </div>
                          ) : (
                            <CodeBlock
                              code={fileContent}
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
        <footer className="text-center p-4 text-sm text-muted-foreground border-t">
            <p>Built for stability and scale.</p>
        </footer>
      </SidebarInset>
    </SidebarProvider>
  );
}
