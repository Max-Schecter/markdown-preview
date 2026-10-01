//
//  MarkdownHTML+HostBridge.swift
//  md-preview
//
//  The MdPreview JS bootstrap injected into every rendered page.
//

import Foundation

// `nonisolated` matters: the targets default to MainActor isolation, and
// rendering runs off the main actor.
nonisolated extension MarkdownHTML {
    // Debug-only perf instrumentation. Routes labelled timings through the
    // host bridge so `[mdp-perf +Xms]` entries land in Xcode's console while
    // diagnosing load-phase regressions. Compiled out of release builds —
    // no-op shims keep call sites unchanged.
    #if DEBUG
    private static let perfBridgeScript = """
    const perfT0 = (typeof performance !== 'undefined' && performance.now)
        ? performance.now() : 0;
    function perfNow() {
        return (typeof performance !== 'undefined' && performance.now)
            ? performance.now() - perfT0 : 0;
    }
    function perfLog(label, detail) {
        const dt = perfNow().toFixed(1);
        const msg = '[mdp-perf +' + dt + 'ms] ' + label
            + (detail !== undefined ? ' ' + detail : '');
        try { post({ kind: 'log', message: msg }); } catch (e) {}
    }
    window.MdPreviewPerf = { now: perfNow, log: perfLog, t0: perfT0 };
    perfLog('script eval');

    if (typeof PerformanceObserver === 'function') {
        try {
            // Disconnect after FCP — paint emits at most two entries
            // (first-paint, first-contentful-paint), no need to keep the
            // observer pinned for the WebView's lifetime.
            const seen = new Set();
            const po = new PerformanceObserver((list) => {
                for (const entry of list.getEntries()) {
                    perfLog('paint:' + entry.name, entry.startTime.toFixed(1) + 'ms');
                    seen.add(entry.name);
                }
                if (seen.has('first-contentful-paint')) po.disconnect();
            });
            po.observe({ type: 'paint', buffered: true });
        } catch (e) {}
    }
    """
    #else
    private static let perfBridgeScript = """
    function perfNow() { return 0; }
    function perfLog() {}
    window.MdPreviewPerf = { now: perfNow, log: perfLog };
    """
    #endif

    // Always-on host bridge: pushes the document height to the AppKit host via
    // a WKScriptMessageHandler instead of having the host poll. Quietly no-ops
    // when the bridge isn't installed (e.g. Quick Look render).
    // Internal so the WebKit regression tests can exercise the exact
    // `MdPreview.update` pipeline shipped by the app with the bundled
    // DOMPurify and morphdom runtimes.
    #if QUICK_LOOK_EXTENSION
    static let allowsRenderedTableEditing = false
    #else
    static let allowsRenderedTableEditing = true
    #endif

    static let hostBridgeScript: String = """
    <script>
    (() => {
        const localized = {
            wrapCode: \(javaScriptStringLiteral(NSLocalizedString("Wrap code", comment: "Code block wrap button"))),
            unwrapCode: \(javaScriptStringLiteral(NSLocalizedString("Unwrap code", comment: "Code block unwrap button"))),
            copyCode: \(javaScriptStringLiteral(NSLocalizedString("Copy code", comment: "Code block copy button accessibility label"))),
            codeCopied: \(javaScriptStringLiteral(NSLocalizedString("Code copied", comment: "Code block copy confirmation accessibility label")))
        };
        let hasHostBridge = false;
        const post = (() => {
            try {
                const h = window.webkit && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.mdPreviewHost;
                if (!h) return () => false;
                hasHostBridge = true;
                return (msg) => {
                    h.postMessage(msg);
                    return true;
                };
            } catch (e) { return () => false; }
        })();

        \(perfBridgeScript)

        function measureHeight() {
            const body = document.body;
            const article = document.querySelector('.markdown-body');
            if (!body || !article) return 1;
            const rect = article.getBoundingClientRect();
            const cs = getComputedStyle(body);
            const pt = parseFloat(cs.paddingTop) || 0;
            const pb = parseFloat(cs.paddingBottom) || 0;
            return Math.max(rect.bottom + pb, pt + article.scrollHeight + pb, 1);
        }

        let last = -1;
        let raf = 0;

        function pushHeight() {
            if (raf) return;
            raf = requestAnimationFrame(() => {
                raf = 0;
                const h = Math.ceil(measureHeight());
                if (h !== last) {
                    last = h;
                    post({ kind: 'height', value: h });
                }
            });
        }

        // Scroll bridge: with compositor-scrolled WKWebView (macOS 26 SDK)
        // the host can't observe scrolling natively — the page reports it.
        let lastScroll = -1;
        let scrollRaf = 0;
        function pushScroll() {
            if (scrollRaf) return;
            scrollRaf = requestAnimationFrame(() => {
                scrollRaf = 0;
                const y = window.scrollY || document.documentElement.scrollTop || 0;
                if (y !== lastScroll) {
                    lastScroll = y;
                    post({ kind: 'scrollPosition', value: y });
                }
            });
        }
        window.addEventListener('scroll', pushScroll, { passive: true });

        window.MdPreviewHost = { pushHeight, measureHeight };

        function elementForEventTarget(target) {
            if (target instanceof Element) return target;
            if (target && target.parentElement instanceof Element) return target.parentElement;
            return document.activeElement instanceof Element ? document.activeElement : null;
        }

        function keyBelongsToFocusedControl(target) {
            const el = elementForEventTarget(target);
            if (!el) return false;
            if (el.isContentEditable) return true;
            return !!el.closest([
                'button',
                'input',
                'select',
                'textarea',
                'summary',
                'audio',
                'video',
                '[contenteditable]',
                '[role="button"]',
                '[role="checkbox"]',
                '[role="switch"]',
                '[role="textbox"]',
                '[role="combobox"]',
                '[role="listbox"]',
                '[role="menuitem"]'
            ].join(','));
        }

        function handlePreviewScrollKey(event) {
            if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.isComposing) return false;
            if (keyBelongsToFocusedControl(event.target)) return false;

            const isSpace = event.key === ' ' || event.key === 'Spacebar' || event.code === 'Space';
            if (isSpace) {
                return post({ kind: 'scroll', value: event.shiftKey ? 'pageUp' : 'pageDown' });
            }

            if (event.shiftKey) return false;
            const key = (event.key || '').toLowerCase();
            if (key === 'j') return post({ kind: 'scroll', value: 'lineDown' });
            if (key === 'k') return post({ kind: 'scroll', value: 'lineUp' });
            return false;
        }

        document.addEventListener('keydown', (event) => {
            if (handlePreviewScrollKey(event)) {
                event.preventDefault();
                event.stopPropagation();
            }
        }, true);

        const codeIcon = (kind) => '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ({
            copy: '<rect x="4" y="8" width="12" height="13" rx="3"/><path d="M8 8V6a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-1"/>',
            check: '<path d="m5 12 4 4L19 6"/>',
            wrap: '<path d="M4 6h16M4 11h12a4 4 0 0 1 0 8h-5m3-3-3 3 3 3M4 16h3"/>',
            unwrap: '<path d="M4 6h16M4 12h16m-4-4 4 4-4 4M4 18h7"/>'
        })[kind] + '</svg>';

        function decorateCodeBlocks(root = document) {
            root.querySelectorAll('pre > code').forEach((code) => {
                const pre = code.parentElement;
                if (!pre || pre.dataset.copyButtonReady === '1') return;
                pre.dataset.copyButtonReady = '1';

                // Wrap pre in a positioned container so the copy button
                // stays pinned regardless of horizontal scroll inside pre.
                const wrap = document.createElement('div');
                wrap.className = 'md-code-wrap';
                pre.parentNode.insertBefore(wrap, pre);
                wrap.appendChild(pre);

                const header = document.createElement('div');
                header.className = 'md-code-header';
                const language = document.createElement('span');
                language.className = 'md-code-language';
                language.textContent = pre.dataset.codeLanguage || 'text';
                header.appendChild(language);
                const toggle = document.createElement('button');
                toggle.type = 'button';
                toggle.className = 'md-code-action md-code-toggle-wrap';
                toggle.innerHTML = codeIcon('wrap');
                toggle.title = localized.wrapCode;
                toggle.setAttribute('aria-label', toggle.title);
                toggle.setAttribute('aria-pressed', 'false');
                header.appendChild(toggle);
                const button = document.createElement('button');
                button.type = 'button';
                button.className = 'md-code-action md-code-copy';
                button.innerHTML = codeIcon('copy');
                button.title = localized.copyCode;
                button.setAttribute('aria-label', localized.copyCode);
                header.appendChild(button);
                wrap.insertBefore(header, pre);
            });
        }

        function selectionFragment(selection) {
            const fragment = document.createDocumentFragment();
            for (let i = 0; i < selection.rangeCount; i += 1) {
                fragment.appendChild(selection.getRangeAt(i).cloneContents());
            }
            const buttons = fragment.querySelectorAll('.md-code-header');
            buttons.forEach((button) => button.remove());
            return { fragment, removedButtons: buttons.length > 0 };
        }

        // Copy as Markdown. The host keeps `window.MdPreview.source` (the
        // document's Markdown) current, and block elements carry their
        // source line range. A selection that covers whole blocks copies
        // those source lines, so lists keep their bullets, links their
        // targets, and code its fences. Partial first or last blocks
        // contribute their selected text; a selection inside one block
        // returns null and copies as text.
        let sourceLineCache = null;
        function sourceLines() {
            const source = window.MdPreview.source;
            if (typeof source !== 'string') return null;
            if (!sourceLineCache || sourceLineCache.source !== source) {
                sourceLineCache = { source, lines: source.split('\\n') };
            }
            return sourceLineCache.lines;
        }
        function sourceSpan(block) {
            const start = Number(block.dataset.sourceStart || block.dataset.sourceLine);
            const end = Number(block.dataset.sourceEnd || block.dataset.sourceLine);
            return Number.isInteger(start) && Number.isInteger(end) && start > 0 && end >= start
                ? { start, end } : null;
        }
        function coversBlockEdge(range, block, edge) {
            const probe = document.createRange();
            probe.selectNodeContents(block);
            if (edge === 'start') probe.setEnd(range.startContainer, range.startOffset);
            else probe.setStart(range.endContainer, range.endOffset);
            return probe.toString().trim() === '';
        }
        function selectedTextWithin(range, block) {
            const clipped = document.createRange();
            clipped.selectNodeContents(block);
            if (clipped.compareBoundaryPoints(Range.START_TO_START, range) < 0) {
                clipped.setStart(range.startContainer, range.startOffset);
            }
            if (clipped.compareBoundaryPoints(Range.END_TO_END, range) > 0) {
                clipped.setEnd(range.endContainer, range.endOffset);
            }
            return clipped.toString();
        }
        function markdownForSelection(selection) {
            selection = selection || window.getSelection();
            const lines = sourceLines();
            if (!lines || !selection || selection.rangeCount !== 1) return null;
            const range = selection.getRangeAt(0);
            if (range.collapsed) return null;
            // Select All ranges over the whole body, so ask for overlap, not
            // containment; the block lookups below stay inside the article.
            const article = document.querySelector('.markdown-body');
            if (!article || !range.intersectsNode(article)) return null;
            // DOM order is not source order: footnote definitions render at
            // the end of the article. Take the earliest source start and the
            // latest source end over every block the selection touches,
            // preferring the innermost block on ties so a partial list item
            // contributes its text while the rest of the list copies as source.
            let startBlock = null, endBlock = null, first = null, last = null;
            for (const block of article.querySelectorAll('[data-source-line]')) {
                if (!range.intersectsNode(block)) continue;
                const span = sourceSpan(block);
                if (!span) continue;
                if (!first || span.start <= first.start) { first = span; startBlock = block; }
                if (!last || span.end >= last.end) { last = span; endBlock = block; }
            }
            if (!startBlock || !endBlock) return null;
            if (last.end < first.start) return null;
            const slice = (from, to) => lines.slice(from - 1, to).join('\\n');
            const startWhole = coversBlockEdge(range, startBlock, 'start');
            const endWhole = coversBlockEdge(range, endBlock, 'end');
            // Nothing rendered lies outside the selection at an edge: extend
            // that edge to the document boundary, so a whole-document copy
            // also carries what renders nothing, such as link reference
            // definitions at the end.
            if (startWhole && coversBlockEdge(range, article, 'start')) first = { start: 1, end: first.end };
            if (endWhole && coversBlockEdge(range, article, 'end')) last = { start: last.start, end: lines.length };
            if (startBlock === endBlock || startBlock.contains(endBlock) || endBlock.contains(startBlock)) {
                if (!startWhole || !endWhole) return null;
                return slice(Math.min(first.start, last.start), Math.max(first.end, last.end));
            }
            if (last.start <= first.end) return null;
            const parts = [];
            parts.push(startWhole ? slice(first.start, first.end) : selectedTextWithin(range, startBlock));
            if (last.start > first.end + 1) parts.push(slice(first.end + 1, last.start - 1));
            parts.push(endWhole ? slice(last.start, last.end) : selectedTextWithin(range, endBlock));
            return parts.join('\\n');
        }

        function plainTextFromFragment(fragment) {
            const div = document.createElement('div');
            div.appendChild(fragment.cloneNode(true));
            return div.innerText || div.textContent || '';
        }

        function htmlFromFragment(fragment) {
            const div = document.createElement('div');
            div.appendChild(fragment.cloneNode(true));
            return div.innerHTML;
        }

        async function copyCodeBlock(button) {
            const wrap = button.closest('.md-code-wrap');
            const code = wrap && wrap.querySelector('pre > code');
            if (!code) return;
            const text = code.textContent || '';
            let copied = false;
            try {
                copied = post({ kind: 'copyCode', value: text });
            } catch (e) {}
            // Quick Look has no host bridge; it registers a dedicated
            // pasteboard handler instead (see quick-look/PreviewViewController).
            if (!copied) {
                try {
                    const handler = window.webkit?.messageHandlers?.mdPreviewCopyCode;
                    if (handler) {
                        handler.postMessage(text);
                        copied = true;
                    }
                } catch (e) {}
            }
            if (!copied && navigator.clipboard && navigator.clipboard.writeText) {
                try {
                    await navigator.clipboard.writeText(text);
                    copied = true;
                } catch (e) {}
            }
            if (!copied) {
                // Last resort for non-secure contexts: execCommand works
                // from a user gesture without clipboard permissions.
                try {
                    const selection = getSelection();
                    const saved = selection && selection.rangeCount
                        ? selection.getRangeAt(0).cloneRange() : null;
                    const range = document.createRange();
                    range.selectNodeContents(code);
                    selection.removeAllRanges();
                    selection.addRange(range);
                    copied = document.execCommand('copy');
                    selection.removeAllRanges();
                    if (saved) selection.addRange(saved);
                } catch (e) {}
            }
            if (!copied) return;
            button.innerHTML = codeIcon('check');
            button.title = localized.codeCopied;
            button.setAttribute('aria-label', localized.codeCopied);
            button.classList.add('is-copied');
            clearTimeout(button.__mdCopyTimer);
            button.__mdCopyTimer = setTimeout(() => {
                button.innerHTML = codeIcon('copy');
                button.title = localized.copyCode;
                button.setAttribute('aria-label', localized.copyCode);
                button.classList.remove('is-copied');
            }, 1100);
        }

        document.addEventListener('click', (event) => {
            const toggle = event.target.closest('.md-code-toggle-wrap');
            if (toggle) {
                event.preventDefault();
                event.stopPropagation();
                const wrapped = toggle.closest('.md-code-wrap').classList.toggle('is-wrapped');
                toggle.setAttribute('aria-pressed', String(wrapped));
                toggle.title = wrapped ? localized.unwrapCode : localized.wrapCode;
                toggle.setAttribute('aria-label', toggle.title);
                toggle.innerHTML = codeIcon(wrapped ? 'unwrap' : 'wrap');
                return;
            }
            const button = event.target.closest('.md-code-copy');
            if (!button) return;
            event.preventDefault();
            event.stopPropagation();
            copyCodeBlock(button);
        });

        // Registered on window so it runs after every document-level copy
        // handler, including the math copy helper that rewrites the plain
        // text of selections containing formulas; the Markdown source
        // already carries the formula source, so it wins when available.
        window.addEventListener('copy', (event) => {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || !event.clipboardData) return;
            const { fragment, removedButtons } = selectionFragment(selection);
            const markdown = markdownForSelection(selection);
            if (markdown !== null) {
                event.clipboardData.setData('text/plain', markdown);
                event.clipboardData.setData('text/html', htmlFromFragment(fragment));
                event.preventDefault();
                return;
            }
            // Another handler already wrote the pasteboard: leave it alone.
            if (event.defaultPrevented) return;
            // Otherwise only step in to keep code copy buttons out of the text.
            if (!removedButtons) return;
            event.clipboardData.setData('text/plain', plainTextFromFragment(fragment));
            event.clipboardData.setData('text/html', htmlFromFragment(fragment));
            event.preventDefault();
        });

        // Vendor lazy-load helpers. rAF is paused while the WKWebView is
        // offscreen (e.g. during the launch-time warmup before the window
        // becomes visible), so afterPaint also falls back to setTimeout(50).
        window.MdPreviewLazy = {
            afterPaint(cb) {
                function tick() {
                    let fired = false;
                    function fire(via) {
                        if (!fired) {
                            fired = true;
                            perfLog('afterPaint fire', via);
                            cb();
                        }
                    }
                    requestAnimationFrame(() => requestAnimationFrame(() => fire('rAF')));
                    setTimeout(() => fire('timeout'), 50);
                }
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', tick, { once: true });
                } else {
                    tick();
                }
            },
            loadScript(src) {
                return new Promise((resolve, reject) => {
                    const tStart = perfNow();
                    perfLog('script append', src);
                    const s = document.createElement('script');
                    s.onload = () => {
                        perfLog('script onload', src + ' (+' + (perfNow() - tStart).toFixed(1) + 'ms)');
                        resolve();
                    };
                    s.onerror = () => reject(new Error('failed: ' + src));
                    s.src = src;
                    document.head.appendChild(s);
                });
            },
            // Wires up a renderer whose vendor JS is loaded after first paint.
            // - registers a reapplier that gates on `loaded`, so fast-path
            //   updates don't fire the renderer before its bundle has arrived
            // - on first paint, fetches `src` (and any `extras` after) and
            //   calls `run`
            lazyRenderer({ src, extras, run }) {
                let loaded = false;
                if (window.MdPreview && window.MdPreview.registerReapplier) {
                    window.MdPreview.registerReapplier(() => { if (loaded) run(); });
                }
                this.afterPaint(async () => {
                    try {
                        await this.loadScript(src);
                        loaded = true;
                        run();
                        if (extras) {
                            for (const e of extras) this.loadScript(e).catch(() => {});
                        }
                    } catch (e) {}
                });
            }
        };

        // DOMPurify config. Closes the raw-HTML XSS path on user markdown
        // (EscapingHTMLFormatter passes block- and inline-HTML through per
        // CommonMark). Inline event handlers, <script>, <iframe>, <object>,
        // <embed>, <base>, <meta>, <link>, <style>, and <form> are dropped;
        // the `style` attribute is stripped to defeat visual-deception
        // attacks against the copy button (display:none segments inside
        // <pre><code> would otherwise survive into clipboard textContent).
        // <button> stays allowed so the mermaid zoom HUD survives sanitize();
        // without a parent <form> (forbidden above), `formaction` has nothing
        // to submit to, and on* handlers are stripped by DOMPurify defaults.
        //
        // ALLOWED_URI_REGEXP extends DOMPurify's default safe-URL list with
        // `md-asset:` so markdown image references that resolve to the
        // document's base directory (![alt](relative/path.png)) keep working.
        const SANITIZE_CONFIG = {
            FORBID_TAGS: ['style', 'form', 'iframe', 'object',
                          'embed', 'meta', 'link', 'base'],
            FORBID_ATTR: ['style'],
            ADD_ATTR: ['target'],
            ALLOWED_URI_REGEXP: /^(?:(?:(?:f|ht)tps?|mailto|tel|callto|sms|cid|xmpp|matrix|md-asset):|[^a-z]|[a-z+.\\-]+(?:[^a-z+.\\-:]|$))/i
        };
        function sanitize(html) {
            if (typeof html !== 'string') return '';
            if (typeof DOMPurify === 'undefined' || !DOMPurify.sanitize) {
                // Fail closed: refuse to render rather than risk shipping
                // unsanitized HTML into innerHTML. This branch fires only if
                // the bundled purify.min.js is missing from the app bundle.
                if (window.console && console.error) {
                    console.error('[md-preview] DOMPurify not loaded; refusing to render article.');
                }
                return '';
            }
            return DOMPurify.sanitize(html, SANITIZE_CONFIG);
        }

        // Incremental-update entry point. Each renderer (KaTeX/Mermaid)
        // registers an idempotent reapplier that re-processes the current
        // article. Same-flag re-renders skip the WKWebView reload entirely.
        const reappliers = [];
        window.MdPreview = window.MdPreview || {};
        window.MdPreview.registerReapplier = (fn) => {
            if (typeof fn === 'function') reappliers.push(fn);
        };
        function enableTaskCheckboxes() {
            document.querySelectorAll('.task-list-item-checkbox').forEach(box => {
                box.disabled = !hasHostBridge;
            });
        }
        document.addEventListener('change', event => {
            const box = event.target;
            if (!hasHostBridge ||
                !box.matches('.task-list-item-checkbox')) return;
            const line = Number(box.closest('[data-source-line]')?.dataset.sourceLine);
            if (!Number.isInteger(line) || line < 1) return;
            post({ kind: 'taskCheckbox', line, checked: box.checked });
        });
        reappliers.push(enableTaskCheckboxes);
        function mdHash(s) {
            let h = 5381;
            for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
            return h.toString(36);
        }

        // One row per expensive block kind: the wrapper class, a key prefix,
        // where the node carrying __mdSrc and the renderer's done flag lives
        // inside the wrapper (null = the wrapper itself), and where the
        // source-position attrs live when not on the wrapper. The keying,
        // preservation, and attr-sync helpers below all derive from this
        // table, so a new renderer means one new row — not three new branches.
        const EXPENSIVE_BLOCKS = [
            { cls: 'mermaid-figure', kind: 'mm',   inner: '.mermaid',   done: 'mmDone',   attrInner: null  },
            { cls: 'md-code-wrap',   kind: 'code', inner: 'pre > code', done: 'hljsDone', attrInner: 'pre' },
            { cls: 'math',           kind: 'math', inner: null,         done: 'mathDone', attrInner: null  }
        ];
        const EXPENSIVE_SELECTOR = EXPENSIVE_BLOCKS.map((b) => '.' + b.cls).join(', ');
        function expensiveKindOf(el) {
            if (!el.classList) return null;
            return EXPENSIVE_BLOCKS.find((b) => el.classList.contains(b.cls)) || null;
        }
        function expensiveSrcNode(el, info) {
            return info.inner ? el.querySelector(info.inner) : el;
        }

        // Content-derived keys so morphdom re-pairs unchanged diagrams/math/
        // code even when blocks are inserted above them. Live nodes hash the
        // stashed __mdSrc (renderers replace textContent with their output);
        // incoming nodes hash textContent — the same Swift emitter produced
        // both strings, so identical source yields identical keys.
        function keyExpensiveBlocks(root) {
            const counts = new Map();
            root.querySelectorAll(EXPENSIVE_SELECTOR).forEach((el) => {
                const info = expensiveKindOf(el);
                const srcNode = expensiveSrcNode(el, info);
                if (!srcNode) return;
                const src = srcNode.__mdSrc !== undefined ? srcNode.__mdSrc : srcNode.textContent;
                // Hash memoized per node — live-tree sources are stable
                // across updates, so only fresh incoming nodes pay the hash.
                // Kind-prefixed so a hash collision can never pair blocks of
                // different types (block math and code wraps are both <div>s).
                let base = srcNode.__mdKeyBase;
                if (base === undefined || srcNode.__mdKeySrc !== src) {
                    base = info.kind + '-' + mdHash(src);
                    srcNode.__mdKeyBase = base;
                    srcNode.__mdKeySrc = src;
                }
                const n = (counts.get(base) || 0) + 1;
                counts.set(base, n);
                el.setAttribute('data-md-key', 'k' + base + ':' + n);
            });
        }

        // A preserved subtree keeps its pre-shift source metadata, which
        // would desync scroll handoff and table edits after lines move.
        // Copy the incoming line attributes onto the live node.
        function syncSourceAttrs(fromEl, toEl, info) {
            let from = fromEl;
            let to = toEl;
            if (info.attrInner) {
                from = fromEl.querySelector(info.attrInner);
                to = toEl.querySelector(info.attrInner);
                if (!from || !to) return;
            }
            for (const name of ['data-source-line', 'data-source-start', 'data-source-end']) {
                const value = to.getAttribute(name);
                if (value === null) from.removeAttribute(name);
                else from.setAttribute(name, value);
            }
        }

        // True when the live subtree holds finished renderer output for the
        // exact source the incoming node carries — morphdom must then leave
        // it untouched. Anything else (still rendering, changed source)
        // morphs normally and the reappliers re-render it.
        function isRenderedForSource(info, fromEl, toEl) {
            const live = expensiveSrcNode(fromEl, info);
            const incoming = expensiveSrcNode(toEl, info);
            return !!live && !!incoming && live.dataset[info.done] === '1'
                && live.__mdSrc === incoming.textContent;
        }

        // Both are stateless, so they're built once instead of per update —
        // MdPreview.update is the per-keystroke-exit/file-change hot path.
        const SANITIZE_DOM_CONFIG = Object.assign({}, SANITIZE_CONFIG, { RETURN_DOM_FRAGMENT: true });
        const MORPH_OPTIONS = {
            childrenOnly: true,
            getNodeKey: (node) => node.nodeType === 1
                ? (node.getAttribute('data-md-key') || node.id || undefined)
                : undefined,
            onBeforeElUpdated: (fromEl, toEl) => {
                if (fromEl.isEqualNode(toEl)) return false;
                // Skipping is all-or-nothing per subtree: letting morphdom
                // descend would strip the done markers (incoming nodes lack
                // them) and force a destructive re-render on the next reapply.
                const info = expensiveKindOf(fromEl);
                if (info && isRenderedForSource(info, fromEl, toEl)) {
                    syncSourceAttrs(fromEl, toEl, info);
                    return false;
                }
                if (fromEl.tagName === 'DETAILS') toEl.toggleAttribute('open', fromEl.open);
                return true;
            }
        };

        // `opts.keepHidden` preserves the warmup opacity so the synthetic
        // Mermaid pre-render doesn't flash on screen. The host then issues a
        // second update without the flag once the real document arrives,
        // which clears the inline style and reveals the article.
        window.MdPreview.markdownForSelection = markdownForSelection;

        function tableCells(table) {
            return Array.from(table.querySelectorAll('thead tr, tbody tr, :scope > tr')).map((row) =>
                Array.from(row.children).filter((cell) => cell.matches('th, td'))
            ).filter((row) => row.length > 0);
        }

        function serializeTable(table) {
            return tableCells(table).map((row) => row.map((cell) => cell.textContent || ''));
        }

        function serializeDirtyRows(table) {
            return tableCells(table).map((row) => row.map((cell) => cell.dataset.mdDirty === '1'));
        }

        function postTableEdit(table, force, actionName) {
            const tableIndex = Number.parseInt(table.dataset.mdTableIndex || '-1', 10);
            if (!Number.isInteger(tableIndex) || tableIndex < 0) return;
            if (!force && table.dataset.mdTableDirty !== '1') return;
            const rows = serializeTable(table);
            const dirtyRows = serializeDirtyRows(table);
            const action = actionName || table.dataset.mdTableActionName || 'Edit Table Cell';
            table.dataset.mdTableDirty = '0';
            delete table.dataset.mdTableActionName;
            tableCells(table).forEach((row) => {
                row.forEach((cell) => {
                    cell.dataset.mdOriginalText = cell.textContent || '';
                    cell.dataset.mdDirty = '0';
                });
            });
            post({ kind: 'tableEdit', tableIndex, rows, dirtyRows, actionName: action });
            pushHeight();
        }

        function makeEditableCell(cell, table, rowIndex, columnIndex) {
            cell.dataset.mdTableEditable = '1';
            cell.dataset.mdRowIndex = String(rowIndex);
            cell.dataset.mdColumnIndex = String(columnIndex);
            cell.setAttribute('spellcheck', 'true');
            cell.setAttribute('role', 'textbox');
            if (cell.dataset.mdOriginalText === undefined) {
                cell.dataset.mdOriginalText = cell.textContent || '';
            }

            if (cell.__mdTableListenersReady) return;
            cell.__mdTableListenersReady = true;
            cell.dataset.mdTableEditReady = '1';

            cell.addEventListener('keydown', (event) => {
                if (event.key === 'Enter') {
                    event.preventDefault();
                    cell.blur();
                }
            });

            cell.addEventListener('paste', (event) => {
                event.preventDefault();
                const text = (event.clipboardData || window.clipboardData)?.getData('text/plain') || '';
                document.execCommand('insertText', false, text.replace(/[\\r\\n]+/g, ' '));
            });

            let timer = 0;
            cell.addEventListener('input', () => {
                if ((cell.textContent || '') === (cell.dataset.mdOriginalText || '')) return;
                table.dataset.mdTableDirty = '1';
                cell.dataset.mdDirty = '1';
                clearTimeout(timer);
                table.dataset.mdTableActionName = 'Edit Table Cell';
                timer = setTimeout(() => postTableEdit(table, false, 'Edit Table Cell'), 120);
            });
            cell.addEventListener('blur', () => {
                clearTimeout(timer);
                if ((cell.textContent || '') !== (cell.dataset.mdOriginalText || '')) {
                    table.dataset.mdTableDirty = '1';
                    cell.dataset.mdDirty = '1';
                    table.dataset.mdTableActionName = 'Edit Table Cell';
                }
                cell.removeAttribute('contenteditable');
                postTableEdit(table, false, 'Edit Table Cell');
            });
        }

        function activateEditableCell(cell) {
            if (!cell || cell.dataset.mdTableEditable !== '1') return false;
            if (cell.getAttribute('contenteditable') !== 'plaintext-only') {
                cell.setAttribute('contenteditable', 'plaintext-only');
            }
            cell.focus({ preventScroll: true });
            return true;
        }

        function decorateTables() {
            if (!hasHostBridge || !\(allowsRenderedTableEditing ? "true" : "false")) return;
            document.querySelectorAll('table[data-md-table-index]').forEach((table) => {
                table.classList.add('md-editable-table');
                const rows = tableCells(table);
                rows.forEach((row, rowIndex) => {
                    row.forEach((cell, columnIndex) => {
                        makeEditableCell(cell, table, rowIndex, columnIndex);
                    });
                });
            });
        }

        function tableContextFromPoint(target, clientX, clientY) {
            const table = target && target.closest
                ? target.closest('table[data-md-table-index]')
                : null;
            if (!table) return;
            let cell = target && target.closest
                ? target.closest('th[data-md-table-editable="1"], td[data-md-table-editable="1"]')
                : null;
            if (!cell || !table.contains(cell)) {
                cell = document.elementFromPoint(clientX, clientY)?.closest(
                    'th[data-md-table-editable="1"], td[data-md-table-editable="1"]'
                );
            }
            if (!cell || !table.contains(cell)) {
                cell = table.querySelector('th[data-md-table-editable="1"], td[data-md-table-editable="1"]');
            }
            if (!cell) return;
            const tableIndex = Number.parseInt(table.dataset.mdTableIndex || '-1', 10);
            const rowIndex = Number.parseInt(cell.dataset.mdRowIndex || '-1', 10);
            const columnIndex = Number.parseInt(cell.dataset.mdColumnIndex || '-1', 10);
            if (![tableIndex, rowIndex, columnIndex].every(Number.isInteger)) return;
            return { tableIndex, rowIndex, columnIndex, clientX, clientY };
        }

        let tableActionSuppressionMS = 900;
        let tableContextMenuDeduplicationMS = 900;
        let editableTableCellSelector = 'th[data-md-table-editable="1"], td[data-md-table-editable="1"]';
        let suppressTableEditClickUntil = 0;
        let suppressTableContextMenuUntil = 0;

        function cancelActiveTableEdit() {
            const active = document.activeElement;
            if (active && active.matches && active.matches(editableTableCellSelector)) {
                active.blur();
            }
        }

        function postTableContextMenu(context) {
            if (!context) return false;
            const now = Date.now();
            suppressTableEditClickUntil = now + tableActionSuppressionMS;
            suppressTableContextMenuUntil = now + tableContextMenuDeduplicationMS;
            cancelActiveTableEdit();
            post({
                kind: 'tableContextMenu',
                tableIndex: context.tableIndex,
                rowIndex: context.rowIndex,
                columnIndex: context.columnIndex,
                clientX: context.clientX,
                clientY: context.clientY
            });
            return true;
        }

        document.addEventListener('contextmenu', (event) => {
            const context = tableContextFromPoint(event.target, event.clientX, event.clientY);
            if (!context) return;
            event.preventDefault();
            event.stopPropagation();
            if (Date.now() < suppressTableContextMenuUntil) return;
            postTableContextMenu(context);
        }, true);

        document.addEventListener('click', (event) => {
            if (Date.now() < suppressTableEditClickUntil) {
                event.preventDefault();
                event.stopPropagation();
                return;
            }
            const cell = event.target && event.target.closest
                ? event.target.closest(editableTableCellSelector)
                : null;
            if (!cell) return;
            activateEditableCell(cell);
        }, true);

        let tableLongPress = null;
        document.addEventListener('touchstart', (event) => {
            if (event.touches.length !== 1) return;
            const touch = event.touches[0];
            const context = tableContextFromPoint(event.target, touch.clientX, touch.clientY);
            if (!context) return;
            tableLongPress = {
                x: touch.clientX,
                y: touch.clientY,
                timer: setTimeout(() => {
                    tableLongPress = null;
                    postTableContextMenu(context);
                }, 550)
            };
        }, { passive: true, capture: true });

        document.addEventListener('touchmove', (event) => {
            if (!tableLongPress || event.touches.length !== 1) return;
            const touch = event.touches[0];
            if (Math.hypot(touch.clientX - tableLongPress.x, touch.clientY - tableLongPress.y) > 10) {
                clearTimeout(tableLongPress.timer);
                tableLongPress = null;
            }
        }, { passive: true, capture: true });

        document.addEventListener('touchend', () => {
            if (!tableLongPress) return;
            clearTimeout(tableLongPress.timer);
            tableLongPress = null;
        }, { passive: true, capture: true });

        document.addEventListener('touchcancel', () => {
            if (!tableLongPress) return;
            clearTimeout(tableLongPress.timer);
            tableLongPress = null;
        }, { passive: true, capture: true });

        window.MdPreviewTables = {
            perform(command, tableIndex, rowIndex, columnIndex) {
                const table = document.querySelector('table[data-md-table-index="' + tableIndex + '"]');
                if (!table) return false;
                const rows = tableCells(table);
                if (!Number.isInteger(rowIndex) || rowIndex < 0 || rowIndex >= rows.length) return false;
                const columnCount = Math.max(1, ...rows.map((row) => row.length));
                if (!Number.isInteger(columnIndex) || columnIndex < 0 || columnIndex >= columnCount) return false;
                const headerCell = rows[0] && rows[0][0] && rows[0][0].tagName === 'TH';
                const actionNames = {
                    insertRowAbove: 'Insert Table Row',
                    insertRowBelow: 'Insert Table Row',
                    deleteRow: 'Delete Table Row',
                    insertColumnBefore: 'Insert Table Column',
                    insertColumnAfter: 'Insert Table Column',
                    deleteColumn: 'Delete Table Column'
                };

                function newCell(forHeader) {
                    const cell = document.createElement(forHeader ? 'th' : 'td');
                    cell.textContent = '';
                    cell.dataset.mdDirty = '1';
                    return cell;
                }

                switch (command) {
                case 'insertRowAbove':
                case 'insertRowBelow': {
                    const reference = rows[rowIndex] && rows[rowIndex][0] && rows[rowIndex][0].parentElement;
                    const parent = reference ? reference.parentElement : table.querySelector('tbody') || table;
                    const tr = document.createElement('tr');
                    const forHeader = rowIndex === 0 && headerCell;
                    for (let i = 0; i < columnCount; i += 1) tr.appendChild(newCell(forHeader));
                    if (reference && command === 'insertRowAbove') {
                        parent.insertBefore(tr, reference);
                    } else if (reference && reference.nextSibling) {
                        parent.insertBefore(tr, reference.nextSibling);
                    } else {
                        parent.appendChild(tr);
                    }
                    break;
                }
                case 'deleteRow': {
                    if (rows.length <= 1) return false;
                    const row = rows[rowIndex] && rows[rowIndex][0] && rows[rowIndex][0].parentElement;
                    if (row) row.remove();
                    break;
                }
                case 'insertColumnBefore':
                case 'insertColumnAfter': {
                    rows.forEach((row, r) => {
                        const insertAt = command === 'insertColumnBefore' ? columnIndex : columnIndex + 1;
                        const cell = newCell(r === 0 && headerCell);
                        const reference = row[Math.min(insertAt, row.length)];
                        const tr = row[0] && row[0].parentElement;
                        if (tr) tr.insertBefore(cell, reference || null);
                    });
                    break;
                }
                case 'deleteColumn': {
                    if (columnCount <= 1) return false;
                    rows.forEach((row) => row[columnIndex]?.remove());
                    break;
                }
                default:
                    return false;
                }

                decorateTables();

                postTableEdit(table, true, actionNames[command] || 'Edit Table');
                return true;
            }
        };


        window.MdPreview.update = (articleHTML, opts) => {
            // The Markdown behind the article, for copy-as-source.
            if (opts && typeof opts.source === 'string') {
                window.MdPreview.source = opts.source;
            }
            // Body swaps can carry a document from a different folder — move
            // the page <base> first so the incoming content's relative URLs
            // resolve against the right folder.
            if (opts && opts.baseHref) {
                const base = document.querySelector('base');
                if (base && base.getAttribute('href') !== opts.baseHref) {
                    base.setAttribute('href', opts.baseHref);
                }
            }
            const article = document.querySelector('.markdown-body');
            if (!article) return;
            const tStart = perfNow();
            // DOM-diff fast path: morph the live article toward the incoming
            // HTML so finished Mermaid SVGs, KaTeX output, and highlighted
            // code survive the update instead of being re-rendered. Skipped
            // for the first populate (empty article), the warmup article,
            // and whenever morphdom or DOMPurify is missing; any throw
            // falls back to the innerHTML swap below.
            const canMorph = !!articleHTML && article.firstElementChild
                && article.dataset.warmup !== '1'
                && typeof morphdom === 'function'
                && typeof DOMPurify !== 'undefined' && DOMPurify.sanitize;
            let morphed = false;
            if (canMorph) {
                try {
                    const frag = DOMPurify.sanitize(articleHTML, SANITIZE_DOM_CONFIG);
                    const next = document.createElement('article');
                    next.appendChild(frag);
                    // Pre-shape the incoming tree so the decorators' wrappers
                    // pair one-to-one with the live DOM during the diff.
                    decorateCodeBlocks(next);
                    keyExpensiveBlocks(article);
                    keyExpensiveBlocks(next);
                    morphdom(article, next, MORPH_OPTIONS);
                    morphed = true;
                } catch (e) {
                    perfLog('morphdom fallback', String(e && e.message || e));
                }
            }
            if (!morphed) {
                article.innerHTML = sanitize(articleHTML);
            }
            if (!opts || !opts.keepHidden) {
                article.style.opacity = '';
                article.style.pointerEvents = '';
                // Revealing means the synthetic warmup content is gone — the
                // hidden populate keeps the flag so the first real document
                // still takes the guaranteed innerHTML replace above, and
                // every update after it may morph.
                delete article.dataset.warmup;
            }
            if (articleHTML) {
                // The morph path already decorated the incoming tree; only
                // the innerHTML swap leaves fresh undecorated nodes behind.
                if (!morphed) {
                    decorateCodeBlocks();
                }
                decorateTables();
                for (const fn of reappliers) {
                    try { fn(); } catch (e) { /* one bad apple shouldn't block others */ }
                }
            }
            perfLog('MdPreview.update' + (morphed ? ' (morphdom)' : ''), '(+' + (perfNow() - tStart).toFixed(1) + 'ms)');
            pushHeight();
        };

        // Initial-load populator. The article body ships inside an inert
        // <template> element so the parser never fires inline event handlers
        // on first paint. Pull it out, sanitize, inject. The template is
        // removed once consumed.
        function populateFromTemplate() {
            const tmpl = document.getElementById('md-article-source');
            if (!tmpl) return;
            const article = document.querySelector('.markdown-body');
            const keepHidden = !!(article && article.dataset.warmup === '1');
            window.MdPreview.update(tmpl.innerHTML, { keepHidden });
            tmpl.remove();
        }
        // Body-end hook: inline-mode documents call this right after the
        // template parses, before the vendor bundles, so text paints early.
        window.MdPreview.populateNow = populateFromTemplate;

        function start() {
            perfLog('start (DOM ready)');
            populateFromTemplate();
            decorateCodeBlocks();
            pushHeight();
            try {
                const ro = new ResizeObserver(pushHeight);
                ro.observe(document.body);
                const article = document.querySelector('.markdown-body');
                if (article) ro.observe(article);
            } catch (e) {}
            window.addEventListener('md-preview-mermaid-rendered', pushHeight);
            window.addEventListener('md-preview-math-rendered', pushHeight);
            window.addEventListener('load', pushHeight);
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', start, { once: true });
        } else {
            start();
        }
    })();
    </script>
    """
}
