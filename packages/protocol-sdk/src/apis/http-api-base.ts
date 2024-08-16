import { retriesGeneric } from "src/retries";

export class BadResponseError<T = any> extends Error {
  status: number;
  json: T;
  constructor(message: string, status: number, json: any) {
    super(message);
    this.name = "BadResponseError";
    this.status = status;
    this.json = json;
  }
}

/**
 * A simple fetch() wrapper for HTTP gets.
 * Can be overridden as needed.
 *
 * @param path Path to run HTTP JSON get against
 * @returns JSON object response
 * @throws Error when HTTP response fails
 */
export const get = async <T>(url: string) => {
  const response = await fetch(url, { method: "GET" });
  if (response.status !== 200) {
    let json;
    try {
      json = await response.json();
    } catch (e: any) {}
    throw new BadResponseError(
      `Invalid response, status ${response.status}`,
      response.status,
      json,
    );
  }
  return (await response.json()) as T;
};

/**
 * A simple fetch() wrapper for HTTP post.
 * Can be overridden as needed.
 *
 * @param path Path to run HTTP JSON POST against
 * @param data Data to POST to the server, converted to JSON
 * @returns JSON object response
 * @throws Error when HTTP response fails
 */
export const post = async <T>(url: string, data: any) => {
  const controller = new AbortController();
  const { signal } = controller;

  // 30 minute timeout:
  const timeout = 30 * 60 * 1000;

  // Set a timeout to automatically abort the request
  const timeoutId = setTimeout(() => controller.abort(), timeout);

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(data),
    signal,
  });

  clearTimeout(timeoutId);
  if (response.status !== 200) {
    let json;
    try {
      json = await response.json();
    } catch (e: any) {}
    throw new BadResponseError(
      `Bad response: ${response.status}`,
      response.status,
      json,
    );
  }
  return (await response.json()) as T;
};

const defaultShouldRetry = (err: any) => {
  return err instanceof BadResponseError && err.status >= 500;
};

export const retries = async <T>(
  tryFn: () => T,
  maxTries: number = 3,
  linearBackoffMS: number = 200,
  shouldRetry: (err: any) => boolean = defaultShouldRetry,
): Promise<T> => {
  return retriesGeneric({
    tryFn,
    maxTries,
    linearBackoffMS,
    shouldRetryOnError: shouldRetry,
  });
};

export interface IHttpClient {
  get: typeof get;
  post: typeof post;
  retries: typeof retries;
}

export const httpClient: IHttpClient = {
  get,
  post,
  retries,
};
