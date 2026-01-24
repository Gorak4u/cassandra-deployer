'use client';

import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Loader2, Github } from 'lucide-react';

import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { useToast } from '@/hooks/use-toast';
import { pushToGit } from '@/lib/actions';

const formSchema = z.object({
  repoUrl: z.string().url({ message: 'Please enter a valid repository URL.' }),
  pat: z.string().min(1, { message: 'Personal Access Token is required.' }),
});

interface GitPushDialogProps {
  isOpen: boolean;
  onOpenChange: (isOpen: boolean) => void;
}

export function GitPushDialog({ isOpen, onOpenChange }: GitPushDialogProps) {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { toast } = useToast();

  const form = useForm<z.infer<typeof formSchema>>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      repoUrl: '',
      pat: '',
    },
  });

  const onSubmit = async (values: z.infer<typeof formSchema>) => {
    setIsSubmitting(true);
    try {
      const result = await pushToGit(values);
      if (result.success) {
        toast({
          title: 'Success',
          description: result.message,
        });
        onOpenChange(false);
        form.reset();
      } else {
        toast({
          variant: 'destructive',
          title: 'Error',
          description: result.message,
        });
      }
    } catch (error) {
      toast({
        variant: 'destructive',
        title: 'An unexpected error occurred',
        description: 'Please check the console for more details.',
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Dialog open={isOpen} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>Push Modules to Git</DialogTitle>
          <DialogDescription>
            Enter your Git repository URL and a Personal Access Token (PAT) to push the modules.
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
            <FormField
              control={form.control}
              name="repoUrl"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Repository URL</FormLabel>
                  <FormControl>
                    <Input placeholder="https://github.com/user/repo.git" {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <FormField
              control={form.control}
              name="pat"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Personal Access Token (PAT)</FormLabel>
                  <FormControl>
                    <Input type="password" placeholder="ghp_..." {...field} />
                  </FormControl>
                  <FormMessage />
                </FormItem>
              )}
            />
            <DialogFooter>
              <Button type="submit" disabled={isSubmitting}>
                {isSubmitting ? (
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                ) : (
                  <Github className="mr-2 h-4 w-4" />
                )}
                {isSubmitting ? 'Pushing...' : 'Push to Git'}
              </Button>
            </DialogFooter>
          </form>
        </Form>
      </DialogContent>
    </Dialog>
  );
}
