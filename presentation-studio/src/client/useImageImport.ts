import { useCallback } from 'react';
import { readImageFile } from './images';
import { useStudio } from './state';

/** Adds image files to the project (drag and drop, file input, or the desktop's native picker). */
export function useImageImport() {
  const { update, putBinary, toast } = useStudio();
  return useCallback(
    async (files: FileList | File[], rejected: string[] = []) => {
      let added = 0;
      for (const f of Array.from(files)) {
        try {
          const { asset, blob } = await readImageFile(f);
          putBinary(asset.id, blob);
          update((d) => {
            d.assets.push(asset);
          });
          added++;
        } catch (e) {
          toast('error', (e as Error).message, 'Accepted: PNG, JPEG and WebP up to 25 MB.');
        }
      }
      for (const r of rejected) toast('error', `Not imported: ${r}`, 'Accepted: PNG, JPEG and WebP up to 25 MB.');
      if (added) toast('success', `Added ${added} image${added === 1 ? '' : 's'}.`);
      return added;
    },
    [update, putBinary, toast],
  );
}
