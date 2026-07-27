import { createElement, Fragment } from 'react';
import { marked } from 'marked';
import type { ReactNode } from 'react';
import type { Token, Tokens } from 'marked';

function safeHref(value: string): string | null {
  const href = value.trim();
  const hasControl = [...href].some(character => {
    const code = character.charCodeAt(0);
    return code <= 31 || code === 127;
  });
  if (
    href !== value
    || href === ''
    || hasControl
    || /^[\\/]{2}/u.test(href)
  ) {
    return null;
  }
  const scheme = href.match(/^([a-z][a-z0-9+.-]*):/i)?.[1].toLowerCase();
  if (scheme) return ['http', 'https', 'mailto'].includes(scheme) ? href : null;
  return href;
}

function MdLink({ token }: { token: Tokens.Link }) {
  const href = safeHref(token.href);
  const children = renderTokens(token.tokens);
  if (!href) return <>{children}</>;
  return <a href={href} title={token.title ?? undefined}>{children}</a>;
}

function MdImage({ token }: { token: Tokens.Image }) {
  return (
    <span className="md-image">
      画像: <span>{renderTokens(token.tokens)}</span>
      {' '}<code>{token.href}</code>
    </span>
  );
}

function MdCode({ token }: { token: Tokens.Code }) {
  const language = token.lang?.trim().split(/\s+/u)[0];
  return (
    <figure className="md-code">
      {language && <figcaption>{language}</figcaption>}
      <pre><code>{token.text}</code></pre>
    </figure>
  );
}

function MdHeading({ token }: { token: Tokens.Heading }) {
  const depth = Math.min(Math.max(token.depth, 1), 6);
  return createElement(`h${depth}`, null, renderTokens(token.tokens));
}

function MdList({ token }: { token: Tokens.List }) {
  const items = token.items.map((item, index) => (
    <li key={index} className={item.task ? 'task' : undefined}>
      {renderTokens(item.tokens)}
    </li>
  ));
  return token.ordered
    ? <ol start={typeof token.start === 'number' ? token.start : undefined}>{items}</ol>
    : <ul>{items}</ul>;
}

function MdQuote({ token }: { token: Tokens.Blockquote }) {
  return <blockquote>{renderTokens(token.tokens)}</blockquote>;
}

function TableCell({
  cell,
  tag,
}: {
  cell: Tokens.TableCell;
  tag: 'td' | 'th';
}) {
  return createElement(
    tag,
    { style: { textAlign: cell.align ?? undefined } },
    renderTokens(cell.tokens),
  );
}

function MdTable({ token }: { token: Tokens.Table }) {
  if (token.header.length > 3) {
    return (
      <div className="md-table-cards">
        {token.rows.map((row, rowIndex) => (
          <dl key={rowIndex}>
            {token.header.map((header, columnIndex) => (
              <Fragment key={columnIndex}>
                <dt>{renderTokens(header.tokens)}</dt>
                <dd>{row[columnIndex] ? renderTokens(row[columnIndex].tokens) : null}</dd>
              </Fragment>
            ))}
          </dl>
        ))}
      </div>
    );
  }
  return (
    <div className="md-table-scroll">
      <table>
        <thead>
          <tr>
            {token.header.map((cell, index) => (
              <TableCell key={index} cell={cell} tag="th" />
            ))}
          </tr>
        </thead>
        <tbody>
          {token.rows.map((row, rowIndex) => (
            <tr key={rowIndex}>
              {row.map((cell, columnIndex) => (
                <TableCell key={columnIndex} cell={cell} tag="td" />
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function tokenNode(token: Token): ReactNode {
  switch (token.type) {
    case 'space':
    case 'def':
    case 'html':
      return null;
    case 'code':
      return <MdCode token={token as Tokens.Code} />;
    case 'heading':
      return <MdHeading token={token as Tokens.Heading} />;
    case 'table':
      return <MdTable token={token as Tokens.Table} />;
    case 'blockquote':
      return <MdQuote token={token as Tokens.Blockquote} />;
    case 'list':
      return <MdList token={token as Tokens.List} />;
    case 'paragraph':
      return <p>{renderTokens((token as Tokens.Paragraph).tokens)}</p>;
    case 'text': {
      const text = token as Tokens.Text;
      return text.tokens ? renderTokens(text.tokens) : text.text;
    }
    case 'escape':
      return (token as Tokens.Escape).text;
    case 'strong':
      return <strong>{renderTokens((token as Tokens.Strong).tokens)}</strong>;
    case 'em':
      return <em>{renderTokens((token as Tokens.Em).tokens)}</em>;
    case 'del':
      return <del>{renderTokens((token as Tokens.Del).tokens)}</del>;
    case 'codespan':
      return <code>{(token as Tokens.Codespan).text}</code>;
    case 'br':
      return <br />;
    case 'hr':
      return <hr />;
    case 'link':
      return <MdLink token={token as Tokens.Link} />;
    case 'image':
      return <MdImage token={token as Tokens.Image} />;
    case 'checkbox':
      return (
        <input
          type="checkbox"
          checked={(token as Tokens.Checkbox).checked}
          readOnly
          aria-label="タスク"
        />
      );
    default: {
      const generic = token as { tokens?: Token[]; text?: unknown };
      if (generic.tokens) return renderTokens(generic.tokens);
      return typeof generic.text === 'string' ? generic.text : null;
    }
  }
}

function renderTokens(tokens: Token[]): ReactNode[] {
  return tokens.map((token, index) => (
    <Fragment key={`${token.type}-${index}`}>{tokenNode(token)}</Fragment>
  ));
}

export function Markdown({
  markdown,
  skipFirstHeading = false,
}: {
  markdown: string;
  skipFirstHeading?: boolean;
}) {
  const tokens = marked.lexer(markdown);
  const visible = skipFirstHeading && tokens[0]?.type === 'heading'
    ? tokens.slice(1)
    : tokens;
  return <div className="markdown">{renderTokens(visible)}</div>;
}
