'use client';

import { useState, type FC } from 'react';
import { Check, Copy } from 'lucide-react';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';

import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';

interface CodeBlockProps {
  code: string;
  language: string;
  className?: string;
}

export const CodeBlock: FC<CodeBlockProps> = ({
  code,
  language,
  className,
}) => {
  const [hasCopied, setHasCopied] = useState(false);

  const copyToClipboard = () => {
    navigator.clipboard.writeText(code).then(() => {
      setHasCopied(true);
      setTimeout(() => {
        setHasCopied(false);
      }, 2000);
    });
  };
  
  const langMap: { [key: string]: string } = {
    puppet: 'ruby',
    bash: 'shell',
  };

  const finalLang = langMap[language] || language;

  return (
    <div className={cn('relative group text-sm font-code', className)}>
      <SyntaxHighlighter
        language={finalLang}
        style={vscDarkPlus}
        showLineNumbers
        wrapLines={true}
        customStyle={{
          margin: 0,
          padding: '1rem',
          paddingTop: '2.5rem',
          borderRadius: '0.375rem',
          border: '1px solid hsl(var(--border))',
          backgroundColor: 'hsl(224, 71%, 4%)'
        }}
        codeTagProps={{
            style: {
                fontFamily: 'var(--font-code)',
            }
        }}
      >
        {code}
      </SyntaxHighlighter>
      <Button
        size="icon"
        variant="ghost"
        className="absolute top-2 right-2 h-8 w-8 text-muted-foreground transition-opacity hover:text-white"
        onClick={copyToClipboard}
      >
        {hasCopied ? (
          <Check className="h-4 w-4 text-green-500" />
        ) : (
          <Copy className="h-4 w-4" />
        )}
        <span className="sr-only">Copy code</span>
      </Button>
    </div>
  );
};
