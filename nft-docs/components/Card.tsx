import {Icons} from './Icons';

function Card({
  title,
  icon,
  href,
  children,
}: {
  title: string;
  href: string;
  icon: keyof typeof Icons;
  children: React.ReactNode;
}) {
  const Icon = Icons[icon];

  return (
    <a href={href} className="BoxCard">
      <Icon />
      <strong>{title}</strong>
      <div>{children}</div>
    </a>
  );
}

function CardContainer({ children }: { children: React.ReactNode }) {
  return <div className="CardContainer">{children}</div>;
}

export { Card, CardContainer };
