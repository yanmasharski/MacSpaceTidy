import Foundation

/// Collects symbolic links under some roots. Does not go into linked folders.
public enum LinkFinder {
    public static func findLinks(roots: [String], maxDepth: Int) -> [LinkInfo] {
        var links: [LinkInfo] = []
        for root in roots {
            if let target = PathTools.linkTarget(root) {
                links.append(LinkInfo(path: root, target: target))
                continue
            }
            collect(folder: root, depthLeft: maxDepth, into: &links)
        }
        return links
    }

    private static func collect(folder: String, depthLeft: Int, into links: inout [LinkInfo]) {
        guard depthLeft > 0 else {
            return
        }
        for child in PathTools.children(of: folder) {
            if let target = PathTools.linkTarget(child) {
                links.append(LinkInfo(path: child, target: target))
            } else if PathTools.isDirectory(child) {
                collect(folder: child, depthLeft: depthLeft - 1, into: &links)
            }
        }
    }
}
