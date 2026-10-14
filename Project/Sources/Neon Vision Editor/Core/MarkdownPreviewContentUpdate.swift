import Foundation

/// Only app-generated preview shells qualify. Shell comparison preserves CSS,
/// CSP, template and runtime scripts; ambiguous markers take the full-load path.
nonisolated enum MarkdownPreviewContentUpdate {
    private static let start = "<!-- nve-preview-content-start -->"
    private static let end = "<!-- nve-preview-content-end -->"

    private static func parts(_ html: String) -> (shell: String, body: String)? {
        guard html.components(separatedBy: start).count == 2,
              html.components(separatedBy: end).count == 2,
              let lower = html.range(of: start), let upper = html.range(of: end),
              lower.upperBound <= upper.lowerBound else { return nil }
        return (String(html[..<lower.upperBound]) + String(html[upper.lowerBound...]),
                String(html[lower.upperBound..<upper.lowerBound]))
    }

    static func script(from previous: String, to next: String) -> String? {
        guard let old = parts(previous), let new = parts(next), old.shell == new.shell,
              let data = try? JSONSerialization.data(withJSONObject: [new.body]),
              let payload = String(data: data, encoding: .utf8) else { return nil }
        // Data is a JSON argument, never interpolated executable markup. Keep
        // unchanged DOM nodes (images/links/selection) and replace changed nodes.
        return """
        (() => {
          const root = document.querySelector('main.content');
          if (!root) return false;
          const body = \(payload)[0];
          if (/<\\s*\\/?\\s*(script|iframe|object|embed|base)\\b/i.test(body)) return false;
          const parsed = new DOMParser().parseFromString('<main>' + body + '</main>', 'text/html');
          const incoming = parsed.querySelector('main');
          if (!incoming || incoming.querySelector('script,iframe,object,embed,base')) return false;
          const ratio = window.scrollY / Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          Array.from(root.childNodes).filter(node => node.nodeType === 8 &&
            ['nve-preview-content-start', 'nve-preview-content-end'].includes(node.textContent.trim()))
            .forEach(node => node.remove());
          root.normalize();
          incoming.normalize();
          const nodes = Array.from(incoming.childNodes);
          nodes.forEach((node, index) => {
            const existing = root.childNodes[index];
            if (!existing) root.appendChild(node);
            else if (!existing.isEqualNode(node)) existing.replaceWith(node);
          });
          while (root.childNodes.length > nodes.length) root.lastChild.remove();
          if (typeof window.__nveEnhanceCodeBlocks === 'function') window.__nveEnhanceCodeBlocks();
          window.scrollTo(0, ratio * Math.max(0, document.documentElement.scrollHeight - window.innerHeight));
          return true;
        })();
        """
    }
}
