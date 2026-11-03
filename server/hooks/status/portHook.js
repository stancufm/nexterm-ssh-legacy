const controlPlane = require("../../lib/controlPlane/ControlPlaneServer");

// Each request covers one target: the engine checks targets serially, while the
// control-plane request itself has a 30-second deadline. Limit concurrent work
// so a large inventory cannot exhaust an engine's worker threads.
const MAX_CONCURRENT_CHECKS = 10;
const MAX_TARGET_TIMEOUT_MS = 25000;

const checkServerStatusBatch = async (entries, timeoutMs = 2000) => {
    if (!controlPlane.hasEngine()) throw new Error("No engine connected");
    const results = [];
    const targets = [];
    for (const entry of entries) {
        const { ip, port, engineId } = entry.config || {};
        if (!ip || !port) {
            results.push({ id: entry.id, status: "offline" });
            continue;
        }
        targets.push({ entry, target: { id: String(entry.id), host: ip, port }, engineId: engineId || null });
    }
    let next = 0;
    const worker = async () => {
        while (next < targets.length) {
            const { entry, target, engineId } = targets[next++];
            try {
                const response = await controlPlane.portCheck([target], Math.max(1, Math.min(timeoutMs, MAX_TARGET_TIMEOUT_MS)), engineId);
                const item = response.entries.find(result => result.id === target.id);
                if (item) results.push({ id: entry.id, status: item.online ? "online" : "offline" });
            } catch (error) {
                // Preserve the existing status if the engine is unavailable or
                // the check itself fails; this is not proof the target is down.
            }
        }
    };
    await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENT_CHECKS, targets.length) }, worker));
    return results;
};

module.exports = { checkServerStatusBatch };
