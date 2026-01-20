import { getPuppetFileTree } from '@/lib/actions';
import { PuppetIDEClient } from '@/components/puppet-ide-client';

export default async function Home() {
  const { allFiles } = await getPuppetFileTree();
  const repoNames = [...new Set(allFiles.map((f) => f.repo))];

  return <PuppetIDEClient allFiles={allFiles} repoNames={repoNames} />;
}
