export const HomePageLogo = ({
  dark,
  light,
}: {
  dark: string;
  light: string;
}) => (
  <div
    className="vocs_HomePage_logo"
    style={{
      height: 60,
    }}
  >
    <img alt="Logo" className="vocs_Logo vocs_Logo_logoDark" src={dark} />
    <img alt="Logo" className="vocs_Logo vocs_Logo_logoLight" src={light} />
  </div>
);
