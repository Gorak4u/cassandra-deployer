'use client';

import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter';
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism';
import { cn } from '@/lib/utils';

interface MarkdownViewProps {
  content: string;
  className?: string;
}

export function MarkdownView({ content, className }: MarkdownViewProps) {
  return (
    <div
      className={cn(
        'prose prose-sm dark:prose-invert max-w-none font-body prose-headings:font-headline prose-headings:tracking-tight prose-p:leading-relaxed prose-a:text-primary hover:prose-a:underline prose-code:bg-muted prose-code:px-1.5 prose-code:py-1 prose-code:rounded prose-code:font-code prose-code:text-foreground prose-table:border prose-th:p-2 prose-td:p-2 prose-th:border prose-td:border',
        className
      )}
    >
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          code({ node, className, children, ...props }) {
            const match = /language-(\w+)/.exec(className || '');
            const codeString = String(children).replace(/\n$/, '');
            return match ? (
              <SyntaxHighlighter
                style={vscDarkPlus}
                language={match[1]}
                showLineNumbers
                wrapLines={true}
                customStyle={{ 
                    margin: 0, 
                    backgroundColor: 'hsl(224, 71%, 4%)',
                    border: '1px solid hsl(var(--border))',
                    borderRadius: '0.375rem',
                }}
                codeTagProps={{
                    style: {
                        fontFamily: 'var(--font-code)',
                    }
                }}
              >
                {codeString}
              </SyntaxHighlighter>
            ) : (
              <code className={className} {...props}>
                {children}
              </code>
            );
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
