
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
import { Terminal, Folder, File as FileIcon, Download } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

const puppetFiles = [
  { group: 'root', name: 'metadata.json', lang: 'json' },
  { group: 'manifests', name: 'init.pp', lang: 'puppet' },
  { group: 'manifests', name: 'params.pp', lang: 'puppet' },
  { group: 'manifests', name: 'install.pp', lang: 'puppet' },
  { group: 'manifests', name: 'config.pp', lang: 'puppet' },
  { group: 'manifests', name: 'service.pp', lang: 'puppet' },
  { group: 'manifests', name: 'java.pp', lang: 'puppet' },
  { group: 'manifests', name: 'firewall.pp', lang: 'puppet' },
  { group: 'templates', name: 'cassandra.yaml.erb', lang: 'yaml' },
  { group: 'templates', name: 'cassandra-rackdc.properties.erb', lang: 'text' },
  { group: 'templates', name: 'jvm-server.options.erb', lang: 'text' },
  { group: 'templates', name: 'cqlshrc.erb', lang: 'text' },
  { group: 'templates', name: 'range-repair.service.erb', lang: 'text' },
  { group: 'templates', name: 'cassandra_limits.conf.erb', lang: 'text' },
  { group: 'templates', name: 'sysctl.conf.epp', lang: 'text' },
  { group: 'scripts', name: 'cassandra-upgrade-precheck.sh', lang: 'bash' },
  { group: 'scripts', name: 'cluster-health.sh', lang: 'bash' },
  { group: 'scripts', name: 'repair-node.sh', lang: 'bash' },
  { group: 'scripts', name: 'cleanup-node.sh', lang: 'bash' },
  { group: 'scripts', name: 'take-snapshot.sh', lang: 'bash' },
  { group: 'scripts', name: 'drain-node.sh', lang: 'bash' },
  { group: 'scripts', name: 'rebuild-node.sh', lang: 'bash' },
  { group: 'scripts', name: 'garbage-collect.sh', lang: 'bash' },
  { group: 'scripts', name: 'assassinate-node.sh', lang: 'bash' },
  { group: 'scripts', name: 'upgrade-sstables.sh', lang: 'bash' },
  { group: 'scripts', name: 'backup-to-s3.sh', lang: 'bash' },
  { group: 'scripts', name: 'prepare-replacement.sh', lang: 'bash' },
  { group: 'scripts', name: 'version-check.sh', lang: 'bash' },
  { group: 'scripts', name: 'cassandra_range_repair.py', lang: 'python' },
  { group: 'scripts', name: 'range-repair.sh', lang: 'bash' },
  { group: 'scripts', name: 'robust_backup.sh', lang: 'bash' },
  { group: 'scripts', name: 'restore_from_backup.sh', lang: 'bash' },
  { group: 'scripts', name: 'node_health_check.sh', lang: 'bash' },
  { group: 'scripts', name: 'rolling_restart.sh', lang: 'bash' },
  { group: 'files', name: 'jamm-0.3.2.jar', lang: 'binary' },
];

type PuppetFile = (typeof puppetFiles)[0];

const puppetFilesByGroup = puppetFiles.reduce((acc, file) => {
  if (!acc[file.group]) {
    acc[file.group] = [];
  }
  acc[file.group].push(file);
  return acc;
}, {} as Record<string, PuppetFile[]>);

const groupOrder = ['root', 'manifests', 'templates', 'scripts', 'files'];
const sortedGroups = Object.entries(puppetFilesByGroup).sort(
  ([a], [b]) => groupOrder.indexOf(a) - groupOrder.indexOf(b)
);

const REPO_NAME = 'profile_ggonda_cassandr';

export default function Home() {
  const [selectedFile, setSelectedFile] = useState<PuppetFile>(
    puppetFiles.find(f => f.name === 'init.pp')!
  );
  const [isDownloading, setIsDownloading] = useState(false);

  const handleDownload = async () => {
    setIsDownloading(true);
    const zip = new JSZip();
    const moduleFolder = zip.folder(REPO_NAME);

    if (moduleFolder) {
      Object.entries(puppetCode).forEach(([group, files]) => {
        const groupFolder = group === 'root' ? moduleFolder : moduleFolder.folder(group);
        if (groupFolder) {
          Object.entries(files).forEach(([fileName, code]) => {
            if (fileName.endsWith('.jar')) {
              // Handle binary file
              groupFolder.file(fileName, 'binary content placeholder', { binary: true });
            } else {
              groupFolder.file(fileName, code as string);
            }
          });
        }
      });
    }
    
    try {
      const content = await zip.generateAsync({ type: 'blob' });
      saveAs(content, `${REPO_NAME}.zip`);
    } catch (error) {
      console.error('Error creating zip file:', error);
    } finally {
      setIsDownloading(false);
    }
  };


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
                Generate a modern Puppet profile for deploying Apache Cassandra.
              </p>
            </div>
          </div>
          <Button onClick={handleDownload} disabled={isDownloading}>
            <Download className="mr-2 h-4 w-4" />
            {isDownloading ? 'Downloading...' : `Download ${REPO_NAME}`}
          </Button>
        </header>

        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div className="lg:col-span-1">
            <Card className="shadow-lg sticky top-8">
              <CardHeader>
                <CardTitle>Puppet Repository</CardTitle>
                <CardDescription>{REPO_NAME}</CardDescription>
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
                                selectedFile.name === file.name &&
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
            <Card className="w-full shadow-lg">
              <CardHeader>
                <CardTitle>{selectedFile.name}</CardTitle>
                <CardDescription>
                  <span className="font-mono text-sm bg-muted px-1 py-0.5 rounded">
                    {REPO_NAME}/{selectedFile.group === 'root'
                      ? selectedFile.name
                      : `${selectedFile.group}/${selectedFile.name}`}
                  </span>
                </CardDescription>
              </CardHeader>
              <CardContent>
                {selectedFile.name === 'init.pp' && (
                  <Alert className="mb-6 border-accent">
                    <Terminal className="h-4 w-4 text-accent" />
                    <AlertTitle>Prerequisites</AlertTitle>
                    <AlertDescription>
                      This profile assumes you have the modules defined in{' '}
                      <code className="font-mono text-sm bg-muted px-1 py-0.5 rounded">
                        metadata.json
                      </code>{' '}
                       installed in your Puppet environment. All other parameters are now driven by Hiera.
                    </AlertDescription>
                  </Alert>
                )}
                <CodeBlock
                  code={
                    (puppetCode as any)[selectedFile.group as keyof typeof puppetCode][
                      selectedFile.name as any
                    ]
                  }
                />
              </CardContent>
            </Card>
          </div>
        </div>

        <footer className="text-center mt-8 text-sm text-muted-foreground">
          <p>Built for stability and scale.</p>
        </footer>
      </div>
    </main>
  );
}
