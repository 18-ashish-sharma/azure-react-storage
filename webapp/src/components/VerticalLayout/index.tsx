import type { ReactNode } from 'react';
import styles from './VerticalLayout.module.css';

interface VerticalLayoutProps {
  /** The main content. */
  children: ReactNode;
  /** Optional header, rendered above the content. */
  header?: ReactNode;
  /** Optional footer, rendered below the content. */
  footer?: ReactNode;
}

/** Full-height column layout: optional header, growing content area, optional footer. */
const VerticalLayout = ({ children, header, footer }: VerticalLayoutProps) => (
  <div className={styles.fullPage}>
    {header && <header className={styles.header}>{header}</header>}
    <main className={styles.content}>{children}</main>
    {footer && <footer className={styles.footer}>{footer}</footer>}
  </div>
);

export default VerticalLayout;
