function Card({
  title,
  icon,
  href,
  children,
}: {
  title: string;
  href: string;
  icon: string;
  children: React.ReactNode;
}) {
  return (
    <a href={href} className="BoxCard">
      <img alt={icon} src={`/brand/${icon}.png`} />
      <strong>{title}</strong>
      <div>{children}</div>
    </a>
  );
}

function CardContainer({ children }: { children: React.ReactNode }) {
  return <div className="CardContainer">{children}</div>;
}

export { Card, CardContainer };
