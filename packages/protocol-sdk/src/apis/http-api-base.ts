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

async function wait(delayMs: number) {
  return new Promise((resolve) => {
    setTimeout(resolve, delayMs);
  });
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
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
    },
    body: JSON.stringify(data),
  });
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

export const retries = async <T>(
  tryFn: () => T,
  maxTries: number = 3,
  atTry: number = 1,
  linearBackoffMS: number = 200,
): Promise<T> => {
  try {
    return await tryFn();
  } catch (err: any) {
    if (err instanceof BadResponseError) {
      if (err.status >= 500) {
        if (atTry <= maxTries) {
          await wait(atTry * linearBackoffMS);
          return await retries(tryFn, maxTries, atTry + 1);
        }
      }
    }
    throw err;
  }
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
