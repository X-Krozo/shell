pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services

Singleton {
    id: root

    property string previousSinkName: ""
    property string previousSourceName: ""

    property list<PwNode> sinks: []
    property list<PwNode> sources: []
    property list<PwNode> streams: []

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property bool muted: !!sink?.audio?.muted
    readonly property real volume: sink?.audio?.volume ?? 0

    readonly property bool sourceMuted: !!source?.audio?.muted
    readonly property real sourceVolume: source?.audio?.volume ?? 0

    readonly property alias cava: cava
    readonly property alias beatTracker: beatTracker

    function setVolume(newVolume: real): void {
        if (sink?.ready && sink?.audio) {
            sink.audio.muted = false;
            sink.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementVolume(amount: real): void {
        setVolume(volume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementVolume(amount: real): void {
        setVolume(volume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setSourceVolume(newVolume: real): void {
        if (source?.ready && source?.audio) {
            source.audio.muted = false;
            source.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function incrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume + (amount || GlobalConfig.services.audioIncrement));
    }

    function decrementSourceVolume(amount: real): void {
        setSourceVolume(sourceVolume - (amount || GlobalConfig.services.audioIncrement));
    }

    function setAudioSink(newSink: PwNode): void {
        Pipewire.preferredDefaultAudioSink = newSink;
    }

    function setAudioSource(newSource: PwNode): void {
        Pipewire.preferredDefaultAudioSource = newSource;
    }

    function cycleNextAudioOutput(): void {
        if (sinks.length === 0)
            return;

        const currentIndex = sinks.findIndex(s => s === sink);
        const nextIndex = (currentIndex + 1) % sinks.length;
        setAudioSink(sinks[nextIndex]);
    }

    function setStreamVolume(stream: PwNode, newVolume: real): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = false;
            stream.audio.volume = Math.max(0, Math.min(GlobalConfig.services.maxVolume, newVolume));
        }
    }

    function setStreamMuted(stream: PwNode, muted: bool): void {
        if (stream?.ready && stream?.audio) {
            stream.audio.muted = muted;
        }
    }

    function getStreamVolume(stream: PwNode): real {
        return stream?.audio?.volume ?? 0;
    }

    function getStreamMuted(stream: PwNode): bool {
        return !!stream?.audio?.muted;
    }

    function getStreamName(stream: PwNode): string {
        if (!stream)
            return Tr.trCtx("Unknown", "unknown audio stream");
        // Try application name first, then description, then name
        return stream.properties["application.name"] || stream.description || stream.name || Tr.trCtx("Unknown application", "unknown application audio stream");
    }

    // Window-class style matching: identity, prefix/contains.

    function namesMatch(a: string, b: string): bool {
        const la = (a ?? "").toLowerCase();
        const lb = (b ?? "").toLowerCase();
        if (!la || !lb)
            return la === lb;
        return la === lb || la.startsWith(lb) || lb.startsWith(la) || la.includes(lb) || lb.includes(la);
    }

    function isAudioAppClass(className: string): bool {
        return root.knownStreamApps.some(n => namesMatch(n, className));
    }

    // Apps proven audio-capable this session (a playback stream connected at
    // least once). The volume dock keeps a GHOST slider for these while one of
    // their windows is open but their stream is disconnected (deep-silenct
    // browsers, players between tracks) — seeded from Hyprland window classes
    // via namesMatch, and pruned when neither a stream nor a window remains.
    property list<string> knownStreamApps: []

    // Per-app remembered volume: ghost sliders read it, and a reconnecting
    // stream gets its remembered value reapplied on (re)connect.
    property var streamVolumes: ({})

    function getGhostVolume(name: string): real {
        return root.streamVolumes[name] ?? 1.0;
    }

    function setGhostVolume(name: string, newVolume: real): void {
        root.streamVolumes = Object.assign({}, root.streamVolumes, { [name]: Math.max(0, Math.min(1, newVolume)) });
    }

    function getAppStream(appName: string): PwNode {
        if (!appName)
            return null;

        const wanted = appName.trim().toLowerCase();
        if (!wanted)
            return null;

        // Try matching each stream's name both ways (identity like "Mozilla firefox" vs
        // stream application.name/node.name "firefox" or "Tauon").
        const exact = root.streams.find(s => (getStreamName(s) || "").toLowerCase() === wanted);
        if (exact)
            return exact;

        const direct = root.streams.find(s => {
            const name = (getStreamName(s) || "").toLowerCase();
            if (!name)
                return false;
            // Either the stream name is contained in the app name, or the app name in it.
            return name.startsWith(wanted) || wanted.startsWith(name) || name.includes(wanted) || wanted.includes(name);
        });
        if (direct)
            return direct;

        // Last resort: token overlap (e.g. identity "Mozilla Firefox" -> stream "firefox").
        const wantedTokens = wanted.split(/[^a-z0-9]+/).filter(t => t.length > 1);
        if (wantedTokens.length > 0) {
            const scored = root.streams.map(s => {
                const name = (getStreamName(s) || "").toLowerCase();
                const tokens = name.split(/[^a-z0-9]+/).filter(t => t.length > 1);
                const overlap = tokens.filter(t => wantedTokens.includes(t)).length;
                return { stream: s, score: overlap };
            }).filter(e => e.score > 0).sort((a, b) => b.score - a.score);
            if (scored.length > 0)
                return scored[0].stream;
        }

        return null;
    }

    function refreshNodes(): void {
        const newSinks = [];
        const newSources = [];
        const newStreams = [];

        for (const node of Pipewire.nodes.values) {
            if (!node.isStream) {
                if (node.isSink)
                    newSinks.push(node);
                else if (node.audio)
                    newSources.push(node);
            // Volumes are per-playback-stream. NOTE: quickshell does not carry
            // "media.class" in node.properties (reads undefined), so capture
            // streams are excluded by name — only the shell's own cava capture
            // ("caelestia-shell") would otherwise pollute this list.
            } else if (node.audio && (node.name ?? "") !== "caelestia-shell") {
                newStreams.push(node);
            }
        }

        // Ghost-slider bookkeeping: remember audio-capable apps, reapply the
        // remembered volume when a stream (re)connects, and prune names once
        // neither a stream nor an open window of the app remains.
        const newNames = newStreams.map(s => getStreamName(s)).filter(n => !!n);
        const oldNames = root.streams.map(s => getStreamName(s));
        for (const name of newNames)
            if (!root.knownStreamApps.includes(name))
                root.knownStreamApps = [...root.knownStreamApps, name];
        for (const stream of newStreams) {
            const name = getStreamName(stream);
            if (name && !oldNames.includes(name) && name in root.streamVolumes)
                setStreamVolume(stream, root.streamVolumes[name]);
        }

        const windowClasses = Hypr.toplevels.values.map(t => String(t.lastIpcObject?.class ?? ""));
        root.knownStreamApps = root.knownStreamApps.filter(name => {
            return newNames.includes(name) || windowClasses.some(c => namesMatch(name, c));
        });
        const snapshot = Object.assign({}, root.streamVolumes);
        for (const stream of newStreams) {
            const name = getStreamName(stream);
            if (name)
                snapshot[name] = getStreamVolume(stream);
        }
        root.streamVolumes = snapshot;

        root.sinks = newSinks;
        root.sources = newSources;
        root.streams = newStreams;
    }

    onSinkChanged: {
        if (!sink?.ready)
            return;

        const newSinkName = sink.description || sink.name || Tr.trCtx("Unknown device", "unknown audio device");

        if (previousSinkName && previousSinkName !== newSinkName && GlobalConfig.utilities.toasts.audioOutputChanged)
            Toaster.toast(Tr.tr("Audio output changed"), Tr.tr("Now using: %1").arg(newSinkName), "volume_up");

        previousSinkName = newSinkName;
    }

    onSourceChanged: {
        if (!source?.ready)
            return;

        const newSourceName = source.description || source.name || Tr.trCtx("Unknown device", "unknown audio device");

        if (previousSourceName && previousSourceName !== newSourceName && GlobalConfig.utilities.toasts.audioInputChanged)
            Toaster.toast(Tr.tr("Audio input changed"), Tr.tr("Now using: %1").arg(newSourceName), "mic");

        previousSourceName = newSourceName;
    }

    // Populate immediately: Pipewire.nodes may already be filled by the time this
    // lazily-loaded singleton is created, so onValuesChanged would never fire.
    Component.onCompleted: {
        refreshNodes();
        previousSinkName = sink?.description || sink?.name || Tr.trCtx("Unknown device", "unknown audio device");
        previousSourceName = source?.description || source?.name || Tr.trCtx("Unknown device", "unknown audio device");
    }

    Connections {
        function onValuesChanged(): void {
            root.refreshNodes();
        }

        target: Pipewire.nodes
    }

    // Always track the current defaults so volume/mute bind even if the lists
    // momentarily lag behind the default node.
    PwObjectTracker {
        objects: [root.sink, root.source, ...root.sinks, ...root.sources, ...root.streams].filter(n => n)
    }

    CavaProvider {
        id: cava

        bars: GlobalConfig.services.visualiserBars
    }

    BeatTracker {
        id: beatTracker
    }

    IpcHandler {
        function cycleOutput(): void {
            root.cycleNextAudioOutput();
        }

        // Debug: list the dock's playback-view rows (label + stream/ghost);
        // remove once the stream/ghost plumbing has shaken down.
        function rows(): string {
            return root.streams.map(s => `stream: ${getStreamName(s)} (client FS target ${s.properties["media.class"] ?? "?"})`)
                .concat(root.knownStreamApps.map(n => `known: ${n}`)).join("\n");
        }

        target: "audio"
    }
}
