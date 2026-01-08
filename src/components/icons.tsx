import type { SVGProps } from 'react';

export function RocketIcon(props: SVGProps<SVGSVGElement>) {
  return (
    <svg
      {...props}
      xmlns="http://www.w3.org/2000/svg"
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4.5 16.5c-1.5 1.5-3 1.5-4.5 0" />
      <path d="M13 8c0-4.4 3.6-8 8-8" />
      <path d="M17.5 4.5c1.5 1.5 1.5 3 0 4.5" />
      <path d="M2 7l1 1" />
      <path d="M7 2l1 1" />
      <path d="m22 22-1.5-1.5" />
      <path d="m17 17-1.5-1.5" />
      <path d="M9 10.5a5.5 5.5 0 0 0-5.5-5.5" />
      <path d="M13.5 15a5.5 5.5 0 0 0 5.5 5.5" />
      <path d="M12 12c.3.3.3.8 0 1.1l-1.1 1.1c-.3.3-.8.3-1.1 0l-1.1-1.1c-.3-.3-.3-.8 0-1.1l1.1-1.1c.3-.3.8-.3 1.1 0Z" />
    </svg>
  );
}
