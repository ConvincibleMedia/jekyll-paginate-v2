# jekyll-paginate-v2 Feature Map

## 1) Purpose and Scope

`jekyll-paginate-v2` is a pagination and index-page generation plugin for Jekyll. It has two major subsystems:

1. A **Pagination Generator** that paginates one or more template pages/documents.
2. An **AutoPages** subsystem that auto-creates tag/category/collection index pages which are then paginated by the generator.

This document combines:

1. Publicly documented features from the README files.
2. Additional behaviour discovered directly in `lib/` (including undocumented and implementation-specific behaviour).

## 2) High-Level Runtime Flow

1. Jekyll invokes `PaginationGenerator`.
2. `AutoPages.create_autopages(site)` runs first and may inject additional pages into `site.pages`.
3. Pagination config is merged from defaults and `_config.yml`.
4. The generator discovers candidate template pages/documents.
5. Each enabled template is paginated into one or more generated pages.
6. Generated pages are attached to `site.pages` or collection docs, with paginator metadata and optional trail metadata.

## 3) Pagination Generator Features

### 3.1 Global and Per-Template Control

1. Global switch: `pagination.enabled`.
2. Per-template switch: front matter `pagination.enabled: true`.
3. Template-level settings override site-wide defaults via deep merge.

### 3.2 Template Discovery

1. Standard behaviour: paginate pages/docs that have `pagination.enabled: true`.
2. **Undocumented:** discovery is configurable via `pagination.search`.
3. `search` can target `pages`, named collections, or collection catch-alls (`all`, `collections`).
4. Search supports path wildcard patterns (`*`) and multiple path patterns per type.
5. Search can include collection documents as pagination templates, not only regular pages.

### 3.3 Content Sources

1. Default source collection: `posts`.
2. Supports single collection, multiple collections, and special `all`.
3. Hidden documents/posts (`hidden: true`) are excluded from pagination inputs.
4. Pagination template documents (`data.pagination`) are excluded from item pools to prevent recursive self-pagination.

### 3.4 Filtering

1. Documented filter keys: category, tag, locale.
2. Legacy keys (`category`, `tag`, `locale`) are migrated into a `filters` hash internally.
3. **Undocumented/intended:** `filters` appears to support richer expressions than README examples, including:
4. String lists (comma/semicolon separated).
5. Regex-like syntax.
6. Numeric/date-like value parsing.
7. Range-style hash filters (`min`/`max`).

### 3.5 Sorting, Offsetting, and Limits

1. Sort key: `sort_field` (supports nested paths with `:` or `.` delimiters).
2. Sort order toggle: `sort_reverse`.
3. Offset support: `offset`.
4. Page count cap: `limit`.
5. Per-page size: `per_page`.

### 3.6 URL, File, and Title Output Control

1. Pagination permalink pattern supports `:num`.
2. Title pattern supports `:title`, `:num`, `:max`.
3. Supports custom output basename via `indexpage`.
4. Supports custom output extension via `extension`.
5. Supports directory-style, file-style, and extensionless permalink outcomes.
6. Template pages with their own `permalink` are respected and combined with pagination paths.

### 3.7 Paginator Object and Liquid Data

1. Standard paginator values: `posts`, `total_pages`, `page`, previous/next, first/last path links, etc.
2. Pagination trail (`page_trail`) is available when configured.
3. Each generated page receives:
4. `pagination_info.curr_page`
5. `pagination_info.total_pages`
6. `autogen: "jekyll-paginate-v2"` on generated pages after page 1.

### 3.8 Pagination Trails

1. Trail controlled by `trail.before` and `trail.after`.
2. Trail entries expose `num`, `path`, `title`.
3. Implementation tries to maintain stable trail length by padding the start/end window when near boundaries.

### 3.9 Compatibility Mode with old `jekyll-paginate`

1. Reads legacy keys (`paginate`, `paginate_path`) when present.
2. Refuses to run both old and new configuration styles simultaneously.
3. Uses legacy-style template resolution and path generation in compatibility mode.

## 4) AutoPages Features

### 4.1 Core Capability

1. Global switch: `autopages.enabled`.
2. Generates index pages for:
3. Tags
4. Categories
5. Collections

### 4.2 Type-Specific Controls

1. Each type has enable flag (`enabled`), layout list (`layouts`), title template, and permalink template.
2. Multiple layouts per type are supported, creating multiple autopages per index key.
3. Logging can be suppressed per type via `silent`.

### 4.3 Slugification

1. Macro placeholders:
2. `:tag`
3. `:cat`
4. `:coll`
5. Slugification config supports mode/case control before macro substitution.

### 4.4 Layout-Level Overrides

1. AutoPage layout files can contain front matter that overrides:
2. `pagination` settings
3. `autopages` settings
4. This allows specialised autopages (for example, filtered collection/tag combinations) without extra Ruby code.

### 4.5 AutoPage Metadata in Liquid

1. Auto-generated template pages carry `page.autopage` metadata.
2. Paginated derivatives carry copied metadata under `page.autopages`.
3. `display_name` preserves the original unnormalised tag/category/collection token for display.

## 5) Undocumented/Internal Behaviours Worth Knowing

1. Pagination template discovery can include collection docs, not only `site.pages`.
2. The generator removes the original pagination template page from site output, then replaces it with generated page 1 and subsequent pages.
3. `PaginationPage` and `PaginationDoc` are synthetic in-memory objects derived from the template.
4. Generated pages keep first-page source `data.path` mapping for plugin compatibility.
5. Collection autopages are built using an internal `__coll` metadata marker while indexing.
6. AutoPages are generated before the paginator pass, so autopages participate in normal paginator processing.

## 6) Current Implementation Caveats (Observed in `lib/`)

These are not just documentation gaps; they materially affect behaviour.

1. `lib/jekyll-paginate-v2/generator/paginationModel.rb` currently has a Ruby parse error at the filter gate (`is_a? Hash`), so the file does not compile as-is.
2. `combine` is read (`config['combine']`) but not applied in pagination decisions.
3. Offset currently calls `pop(offset_count)`, which removes items from the tail, not the head.
4. Several debug `puts` statements are unconditional, causing noisy console output.
5. AutoPages README examples use `slugify.case`, while code expects `slugify.cased`.
6. AutoPages defaults in code use slugify mode `none`, while README examples show `default`.
7. Legacy compatibility logic is still present, but date-based retirement checks are long past and may make compatibility mode unusable in modern runs.

## 7) Practical Configuration Surface (Consolidated)

### 7.1 Pagination keys

`enabled`, `search`, `collection`, `offset`, `per_page`, `permalink`, `title`, `page_num`, `sort_reverse`, `sort_field`, `limit`, `trail.before`, `trail.after`, `indexpage`, `extension`, `debug`, `legacy`, plus migrated `filters` from `category/tag/locale`.

### 7.2 AutoPages keys

`enabled`, and per type (`tags`, `categories`, `collections`): `enabled`, `layouts`, `title`, `permalink`, `silent`, `slugify.mode`, `slugify.cased`.

## 8) Feature Status Summary

1. The codebase contains a rich feature set beyond README coverage, especially around template discovery and filter expression capability.
2. The feature surface includes both mature/documented features and implementation-specific behaviour.
3. Some advanced paths are presently inconsistent or broken in this branch and should be treated as provisional until repaired and regression-tested.
