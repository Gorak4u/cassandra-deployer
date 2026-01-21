'use server';
/**
 * @fileOverview A code validation AI agent.
 *
 * - validateCode - A function that handles the code validation process.
 * - ValidateCodeInput - The input type for the validateCode function.
 * - ValidateCodeOutput - The return type for the validateCode function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const ValidateCodeInputSchema = z.object({
  code: z.string().describe('The source code to validate.'),
  language: z.string().describe('The programming language of the code (e.g., "puppet", "ruby", "bash").'),
});
export type ValidateCodeInput = z.infer<typeof ValidateCodeInputSchema>;

const ValidateCodeOutputSchema = z.object({
  isValid: z.boolean().describe('Whether the code is valid with no errors.'),
  issues: z.array(z.string()).describe('A list of issues or errors found in the code. Empty if isValid is true.'),
});
export type ValidateCodeOutput = z.infer<typeof ValidateCodeOutputSchema>;

export async function validateCode(input: ValidateCodeInput): Promise<ValidateCodeOutput> {
  return validateCodeFlow(input);
}

const languageMap: Record<string, string> = {
    puppet: 'Puppet',
    ruby: 'Ruby (ERB)',
    bash: 'Bash (Shell script)',
    python: 'Python',
    yaml: 'YAML',
    json: 'JSON',
    markdown: 'Markdown',
    text: 'Plain Text'
}

const validateCodeFlow = ai.defineFlow(
  {
    name: 'validateCodeFlow',
    inputSchema: ValidateCodeInputSchema,
    outputSchema: ValidateCodeOutputSchema,
  },
  async ({ code, language }) => {
    const fullLanguageName = languageMap[language] || language;

    const { output } = await ai.generate({
        prompt: `You are an expert code linter and validator. Your task is to analyze the provided code snippet and determine if it is syntactically valid and follows best practices for the given language.

Language: ${fullLanguageName}

Code to validate:
\`\`\`${language}
${code}
\`\`\`

Analyze the code for the following:
1.  Syntax errors.
2.  Common programming mistakes or anti-patterns.
3.  Style guide violations for the language.

Your response must be in the specified JSON format.
If there are no errors of any kind, set "isValid" to true and "issues" to an empty array.
If you find any issues, set "isValid" to false and provide a concise, one-sentence description of each issue in the "issues" array. Focus on the most critical issues first.
`,
        output: {
            schema: ValidateCodeOutputSchema,
        },
        model: 'googleai/gemini-2.5-flash',
    });

    return output!;
  }
);
