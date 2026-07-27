import {
  dirname,
  isAbsolute,
  relative,
  resolve,
} from 'node:path';
import {
  lstatSync,
  mkdirSync,
  realpathSync,
} from 'node:fs';

export class ContainmentError extends Error {}

function isInside(parent: string, child: string): boolean {
  const path = relative(parent, child);
  return path === '' || (!path.startsWith('..') && !isAbsolute(path));
}

function nearestExisting(path: string): string {
  let current = path;
  while (true) {
    try {
      lstatSync(current);
      return current;
    } catch {
      const parent = dirname(current);
      if (parent === current) throw new ContainmentError(`path has no existing parent: ${path}`);
      current = parent;
    }
  }
}

export function containedPath(
  workDir: string,
  relativePath: string,
  createParent = false,
): string {
  const absoluteWorkDir = resolve(workDir);
  const target = resolve(absoluteWorkDir, relativePath);
  if (!isInside(absoluteWorkDir, target)) {
    throw new ContainmentError(`path escapes work directory: ${relativePath}`);
  }

  let realWorkDir: string;
  try {
    realWorkDir = realpathSync(absoluteWorkDir);
  } catch {
    throw new ContainmentError(`work directory is missing: ${workDir}`);
  }

  const parent = dirname(target);
  let realExistingParent: string;
  try {
    realExistingParent = realpathSync(nearestExisting(parent));
  } catch {
    throw new ContainmentError(`path parent cannot be resolved: ${relativePath}`);
  }
  if (!isInside(realWorkDir, realExistingParent)) {
    throw new ContainmentError(`path parent escapes work directory: ${relativePath}`);
  }

  let parentExists = false;
  try {
    lstatSync(parent);
    parentExists = true;
  } catch {
    // The nearest existing ancestor was checked above.
  }
  if (!parentExists && !createParent) return target;
  if (!parentExists) mkdirSync(parent, { recursive: true });

  let realParent: string;
  try {
    realParent = realpathSync(parent);
  } catch {
    throw new ContainmentError(`path parent is unavailable: ${relativePath}`);
  }
  if (!isInside(realWorkDir, realParent)) {
    throw new ContainmentError(`path parent escapes work directory: ${relativePath}`);
  }

  try {
    lstatSync(target);
    const realTarget = realpathSync(target);
    if (!isInside(realWorkDir, realTarget)) {
      throw new ContainmentError(`path escapes work directory: ${relativePath}`);
    }
  } catch (error) {
    if (error instanceof ContainmentError) throw error;
    try {
      lstatSync(target);
      throw new ContainmentError(`path cannot be resolved: ${relativePath}`);
    } catch (nestedError) {
      if (nestedError instanceof ContainmentError) throw nestedError;
    }
  }

  return target;
}
