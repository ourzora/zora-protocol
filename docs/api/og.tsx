import { ImageResponse } from "@vercel/og";

export const config = {
  runtime: "experimental-edge",
};

export default function GET(request: Request) {
  const { searchParams } = new URL(request.url);

  const title = searchParams.get("title");
  const description = searchParams.get("description");

  return new ImageResponse(
    (
      <div
        style={{
          display: "flex",
          fontSize: 128,
          background: "white",
          width: "100%",
          height: "100%",
          gap: 40,
        }}
      >
        <img src="/og-trim.png" alt="ZORA" />
        {title && <div style={{}}>{title}</div>}
        {description && <div style={{ fontSize: 18 }}>{description}</div>}
      </div>
    ),
  );
}
