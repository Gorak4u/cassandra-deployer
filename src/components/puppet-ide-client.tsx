'use client';

import dynamic from 'next/dynamic';
import type { PuppetFile } from '@/lib/actions';
import { Skeleton } from '@/components/ui/skeleton';

// Dynamically import the PuppetIDE component with SSR disabled
const PuppetIDE = dynamic(
  () => import('@/components/puppet-ide').then((mod) => mod.PuppetIDE),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-screen w-full font-body">
        <div className="hidden md:flex flex-col w-[280px] border-r bg-card p-4 gap-4">
          <div className="flex items-center gap-3">
            <Skeleton className="h-10 w-10 rounded-lg" />
            <Skeleton className="h-6 w-3/4" />
          </div>
          <Skeleton className="h-10 w-full" />
          <div className="space-y-3 mt-2">
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
            <Skeleton className="h-8 w-full" />
          </div>
          <div className="flex-grow"></div>
          <Skeleton className="h-10 w-full" />
        </div>
        <div className="flex-1 flex flex-col">
          <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b bg-background/95 backdrop-blur-sm px-4 lg:h-[60px] lg:px-6">
            <Skeleton className="h-8 w-8 md:hidden" />
            <div className="flex-1">
              <Skeleton className="h-6 w-1/2 md:w-1/4" />
            </div>
          </header>
          <div className="flex-1 p-4 md:p-6 lg:p-8">
            <Skeleton className="h-full w-full rounded-lg" />
          </div>
        </div>
      </div>
    ),
  }
);

interface PuppetIDEClientProps {
  allFiles: PuppetFile[];
  repoNames: string[];
}

// This is the Client Component that will render the dynamic PuppetIDE
export function PuppetIDEClient({ allFiles, repoNames }: PuppetIDEClientProps) {
  return <PuppetIDE allFiles={allFiles} repoNames={repoNames} />;
}
