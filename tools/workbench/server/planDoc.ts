import { createHash } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { containedPath } from './contained.js';
import type {
  ParsedPlanNode,
  PlanDocument,
  PlanLevel,
} from './planTypes.js';

export class PlanNotFoundError extends Error {}

type Heading = {
  depth: number;
  title: string;
  normalizedTitle: string;
  start: number;
  bodyStart: number;
};

type Section = Heading & {
  end: number;
  children: Section[];
};

const LEVELS = new Map<string, PlanLevel>([
  ['概要', 'focus'],
  ['判断', 'decision'],
  ['方針', 'focus'],
  ['現状の作り', 'detail'],
  ['実装手順', 'detail'],
  ['リスク', 'focus'],
]);

function sha256(value: string | Buffer): string {
  return createHash('sha256').update(value).digest('hex');
}

function normalizeHeading(value: string): string {
  return value
    .normalize('NFKC')
    .trim()
    .replace(/\s+#+\s*$/u, '')
    .trim();
}

function normalizeText(value: string): string {
  return value
    .normalize('NFKC')
    .replace(/\r\n?/g, '\n')
    .split('\n')
    .map(line => line.trimEnd())
    .join('\n')
    .trim();
}

function quoteFor(value: string): string | undefined {
  const quote = value
    .normalize('NFKC')
    .replace(/\s+/gu, ' ')
    .trim()
    .slice(0, 120);
  return quote || undefined;
}

function hasBody(value: string): boolean {
  return value.replace(/<!--[\s\S]*?-->/g, '').trim() !== '';
}

function scanHeadings(source: string): Heading[] {
  const headings: Heading[] = [];
  let offset = 0;
  let htmlComment = false;
  let fence: {
    marker: '`' | '~';
    length: number;
    maxIndent: number;
  } | null = null;

  for (const lineWithEnding of source.match(/[^\n]*(?:\n|$)/g) ?? []) {
    if (!lineWithEnding) continue;
    const line = lineWithEnding.replace(/\r?\n$/, '');

    if (fence) {
      const close = line.match(/^( *)(`+|~+)[ \t]*$/);
      if (
        close
        && close[1].length <= fence.maxIndent
        && close[2][0] === fence.marker
        && close[2].length >= fence.length
      ) {
        fence = null;
      }
      offset += lineWithEnding.length;
      continue;
    }

    let scanLine = line;
    if (htmlComment) {
      scanLine = ' '.repeat(line.length);
      if (line.includes('-->')) htmlComment = false;
    } else if (/^ {0,3}<!--/.test(line)) {
      scanLine = ' '.repeat(line.length);
      if (!line.includes('-->')) htmlComment = true;
    }

    const listOpen = scanLine.match(
      /^( {0,3}(?:[-+*]|\d+[.)])[ \t]+)(`{3,}|~{3,})(.*)$/,
    );
    const directOpen = scanLine.match(/^( {0,3})(`{3,}|~{3,})(.*)$/);
    const open = listOpen ?? directOpen;
    if (open) {
      fence = {
        marker: open[2][0] as '`' | '~',
        length: open[2].length,
        maxIndent: listOpen ? open[1].length + 3 : 3,
      };
      offset += lineWithEnding.length;
      continue;
    }

    const match = scanLine.match(
      /^ {0,3}(#{1,6})(?:[ \t\u3000]+(.*)|[ \t\u3000]*)$/u,
    );
    if (match) {
      const rawTitle = (match[2] ?? '').replace(/[ \t\u3000]+#+[ \t\u3000]*$/u, '').trim();
      headings.push({
        depth: match[1].length,
        title: rawTitle,
        normalizedTitle: normalizeHeading(rawTitle),
        start: offset,
        bodyStart: offset + lineWithEnding.length,
      });
    }
    offset += lineWithEnding.length;
  }

  return headings;
}

function sectionTree(headings: Heading[], sourceLength: number): Section[] {
  const roots: Section[] = [];
  const stack: Section[] = [];

  for (const heading of headings) {
    while (stack.length && stack[stack.length - 1].depth >= heading.depth) {
      const completed = stack.pop();
      if (completed) completed.end = heading.start;
    }
    const section: Section = {
      ...heading,
      end: sourceLength,
      children: [],
    };
    const parent = stack[stack.length - 1];
    if (parent) parent.children.push(section);
    else roots.push(section);
    stack.push(section);
  }

  return roots;
}

function nodeHash(title: string, body: string): string {
  return sha256(`${normalizeHeading(title)}\n${normalizeText(body)}`).slice(0, 12);
}

export function readPlan(workDir: string): PlanDocument {
  const path = containedPath(workDir, 'plan.md');
  if (!existsSync(path)) throw new PlanNotFoundError('plan not found');

  const bytes = readFileSync(path);
  const source = bytes.toString('utf8');
  const scanned = scanHeadings(source);
  const documentTitle = scanned[0]?.depth === 1 ? scanned.shift() : undefined;
  const sections = sectionTree(scanned, source.length);
  const nodes: ParsedPlanNode[] = [];
  const warnings: string[] = [];
  let nextKey = 1;

  const visit = (
    section: Section,
    parentKey: string,
    index: number,
    inheritedLevel: PlanLevel,
  ): ParsedPlanNode => {
    const key = `p${nextKey++}`;
    const ownLevel = LEVELS.get(section.normalizedTitle);
    const level = ownLevel ?? inheritedLevel;
    const firstChild = section.children[0];
    const preambleEnd = firstChild?.start ?? section.end;
    const body = source.slice(section.bodyStart, preambleEnd);
    const hasPreamble = section.children.length > 0 && hasBody(body);
    const leafBody = source.slice(section.bodyStart, section.end);
    const isReviewLeaf = section.children.length === 0 && hasBody(leafBody);
    const childNodes: ParsedPlanNode[] = [];
    const node: ParsedPlanNode = {
      key,
      parentKey,
      index,
      title: section.title,
      depth: section.depth,
      kind: 'section',
      hash: '',
      level,
      leaf: isReviewLeaf,
      markdown: source.slice(section.start, section.end),
    };
    nodes.push(node);

    if (!ownLevel && parentKey === '@doc') {
      warnings.push(`標準にない節名: ${section.title || '(空の見出し)'}`);
    }

    if (hasPreamble) {
      const preamble: ParsedPlanNode = {
        key: `p${nextKey++}`,
        parentKey: key,
        index: 0,
        title: section.title,
        depth: Math.min(section.depth + 1, 6),
        kind: 'preamble',
        hash: nodeHash(section.title, body),
        quote: quoteFor(body),
        level,
        leaf: true,
        markdown: body,
      };
      nodes.push(preamble);
      childNodes.push(preamble);
    }

    for (const child of section.children) {
      childNodes.push(visit(
        child,
        key,
        childNodes.length,
        level,
      ));
    }

    if (section.children.length === 0) {
      node.hash = nodeHash(section.title, leafBody);
      if (node.leaf) node.quote = quoteFor(leafBody);
    } else {
      node.hash = sha256([
        normalizeHeading(section.title),
        normalizeText(body),
        ...childNodes.map(child => child.hash),
      ].join('\n')).slice(0, 12);
    }
    return node;
  };

  const rootChildren = sections.map((section, index) =>
    visit(section, '@doc', index, 'focus'));
  const rootBodyEnd = sections[0]?.start ?? source.length;
  const rootBodyStart = documentTitle?.bodyStart ?? 0;
  nodes.unshift({
    key: '@doc',
    parentKey: null,
    index: 0,
    title: documentTitle?.title || 'Plan',
    depth: 0,
    kind: 'document',
    hash: sha256([
      normalizeHeading(documentTitle?.title ?? ''),
      normalizeText(source.slice(rootBodyStart, rootBodyEnd)),
      ...rootChildren.map(child => child.hash),
    ].join('\n')).slice(0, 12),
    level: 'focus',
    leaf: false,
    markdown: source,
  });

  return {
    hash: sha256(bytes),
    nodes,
    warnings,
  };
}
