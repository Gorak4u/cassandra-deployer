import { getPuppetFileTree } from '@/lib/actions';
import { PuppetIDE } from '@/components/puppet-ide';
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
import { RocketIcon } from '@/components/icons';
import { Download, Package } from 'lucide-react';
import { Button } from '@/components/ui/button';

export default async function Home() {
  const { allFiles } = await getPuppetFileTree();
  const repoNames = [...new Set(allFiles.map(f => f.repo))];

  return (
     <PuppetIDE allFiles={allFiles} repoNames={repoNames} />
  );
}
