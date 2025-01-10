export async function retries<T>(
  fn: () => Promise<T>,
  maxRetries: number,
  delay: number,
  shouldRetry: (error: any) => boolean,
): Promise<T> {
  let lastError: any;

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      if (!shouldRetry(error)) {
        throw error;
      }
      if (i < maxRetries - 1) {
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}
