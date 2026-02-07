import { defineCollection, z } from 'astro:content';

const posts = defineCollection({
  type: 'content',
  schema: z.object({
    title: z.string(),
    subtitle: z.string(),
    date: z.date(),
    readTime: z.string(),
    category: z.enum(['Research', 'Technical', 'Essay', 'Update']),
    tags: z.array(z.string()),
    author: z.string(),
    featured: z.boolean().optional(),
    draft: z.boolean().optional(),
    image: z.string().optional(),
  }),
});

export const collections = { posts };
