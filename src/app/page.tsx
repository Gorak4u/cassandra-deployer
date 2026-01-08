import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { RocketIcon } from '@/components/icons';
import { CodeBlock } from '@/components/code-block';
import { puppetCode } from '@/lib/puppet-code';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Terminal } from 'lucide-react';

const puppetFiles = [
  { group: 'manifests', name: 'init.pp', lang: 'puppet' },
  { group: 'manifests', name: 'params.pp', lang: 'puppet' },
  { group: 'manifests', name: 'java.pp', lang: 'puppet' },
  { group: 'manifests', name: 'install.pp', lang: 'puppet' },
  { group: 'manifests', name: 'config.pp', lang: 'puppet' },
  { group: 'manifests', name: 'service.pp', lang: 'puppet' },
  { group: 'templates', name: 'cassandra.yaml.erb', lang: 'yaml' },
  { group: 'files', name: 'cassandra-env.sh', lang: 'bash' },
  { group: 'scripts', name: 'backup.sh', lang: 'bash' },
];

export default function Home() {
  return (
    <main className="min-h-screen bg-background font-body text-foreground">
      <div className="container mx-auto p-4 md:p-8">
        <header className="flex items-center gap-4 mb-8">
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
        </header>

        <Card className="w-full shadow-lg">
          <CardHeader>
            <CardTitle>Puppet Profile: profile_ggonda_cassandra</CardTitle>
            <CardDescription>
              Below is a complete, OS-agnostic Puppet profile for Cassandra. It
              uses Hiera for dynamic configuration and follows modern Puppet
              practices.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Alert className="mb-6 border-accent">
              <Terminal className="h-4 w-4 text-accent" />
              <AlertTitle>Prerequisites</AlertTitle>
              <AlertDescription>
                This profile assumes you have the{' '}
                <code className="font-mono text-sm bg-muted px-1 py-0.5 rounded">
                  puppetlabs/stdlib
                </code>{' '}
                and{' '}
                <code className="font-mono text-sm bg-muted px-1 py-0.5 rounded">
                  puppetlabs/apt
                </code>{' '}
                modules installed in your Puppet environment.
              </AlertDescription>
            </Alert>
            <Tabs defaultValue="init.pp" className="w-full">
              <TabsList className="grid w-full grid-cols-3 gap-1 sm:grid-cols-4 md:grid-cols-5 lg:grid-cols-9 h-auto">
                {puppetFiles.map((file) => (
                  <TabsTrigger key={file.name} value={file.name}>
                    {file.name}
                  </TabsTrigger>
                ))}
              </TabsList>

              {puppetFiles.map((file) => (
                <TabsContent key={file.name} value={file.name} className="mt-4">
                  <div className="text-sm text-muted-foreground mb-2 font-mono">
                    <span className="font-semibold text-foreground">
                      Path:
                    </span>{' '}
                    profile_ggonda_cassandra/{file.group}/{file.name}
                  </div>
                  <CodeBlock
                    code={
                      puppetCode[file.group as keyof typeof puppetCode][
                        file.name as any
                      ]
                    }
                  />
                </TabsContent>
              ))}
            </Tabs>
          </CardContent>
        </Card>

        <footer className="text-center mt-8 text-sm text-muted-foreground">
          <p>Built with stability and reliability in mind.</p>
        </footer>
      </div>
    </main>
  );
}
