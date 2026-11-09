export function isIndexSection(item) {
  return Array.isArray(item.items);
}

export function sectionLinks(section) {
  return (
    section.items?.filter((item) => !isIndexSection(item)) ?? section.links
  );
}

export function* sectionEntries(sections, ancestors = []) {
  for (const section of sections) {
    yield { section, ancestors };
    const children = section.items?.filter(isIndexSection) ?? [];
    yield* sectionEntries(children, [...ancestors, section]);
  }
}

export function sectionHeight(section) {
  const children = section.items.filter(isIndexSection);
  return 1 + Math.max(0, ...children.map(sectionHeight));
}
