import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "config_engine.js" as Engine

PluginComponent {
    id: root

    property bool proxyEnabled: false
    property bool serviceRunning: false
    property string proxyStatus: "disabled"
    property string pendingOperation: ""
    property real networkRxRate: 0
    property real networkTxRate: 0
    property string daeConfigDir: "/home/dalin/.config/dae"
    property string daeConfigPath: daeConfigDir + "/config.dae"

    property var subscriptions: []
    property var nodePool: []
    property var groups: [{"name":"proxy","nodes":[],"isActive":false}]
    property var activeNodes: []
    property var latencyMap: ({})
    property var testQueue: []
    property string addTarget: "proxy"

    popoutWidth: 400
    popoutContent: proxyPanelComponent
    pillRightClickAction: function() { root.toggleProxy() }

    onPluginServiceChanged: {
        if (!pluginService) return
        root.proxyEnabled = pluginService.loadPluginData("dae-proxy-widget", "proxyEnabled", false)
        root.serviceRunning = pluginService.loadPluginData("dae-proxy-widget", "serviceRunning", false)
        try { var s = pluginService.loadPluginData("dae-proxy-widget", "subscriptions", ""); if (s) root.subscriptions = JSON.parse(s) } catch (e) {}
        try { var g = pluginService.loadPluginData("dae-proxy-widget", "groups", ""); if (g) root.groups = JSON.parse(g) } catch (e) {}
        try { var n = pluginService.loadPluginData("dae-proxy-widget", "nodes", ""); if (n) root.nodePool = JSON.parse(n) } catch (e) {}
        try { var lm = pluginService.loadPluginData("dae-proxy-widget", "latencyMap", "{}"); if (lm) root.latencyMap = JSON.parse(lm) } catch (e) {}
        ensureDefaultGroup()
        syncActiveNodesFromGroups()
    }
    function syncActiveNodesFromGroups() {
        var active = []
        for (var g = 0; g < root.groups.length; g++) {
            if (root.groups[g].isActive) {
                var ns = root.groups[g].nodes || []
                for (var n = 0; n < ns.length; n++) active.push(ns[n].name)
                break
            }
        }
        root.activeNodes = active
    }

    function formatNetworkSpeed(b) {
        if (b < 1024) return b.toFixed(0) + " B/s"
        if (b < 1048576) return (b / 1024).toFixed(1) + " KB/s"
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB/s"
        return (b / 1073741824).toFixed(1) + " GB/s"
    }
    function isHighSpeed() { return root.networkRxRate > 2097152 || root.networkTxRate > 2097152 }
    function ensureDefaultGroup() {
        for (var i = 0; i < root.groups.length; i++) { if (root.groups[i].name === "proxy") return }
        var ng = root.groups.slice(); ng.unshift({ name: "proxy", nodes: [], isActive: false }); root.groups = ng
    }
    function persistData() {
        if (!pluginService) return
        root.ensureDefaultGroup()
        pluginService.savePluginData("dae-proxy-widget", "proxyEnabled", root.proxyEnabled)
        pluginService.savePluginData("dae-proxy-widget", "serviceRunning", root.serviceRunning)
        pluginService.savePluginData("dae-proxy-widget", "subscriptions", JSON.stringify(root.subscriptions))
        pluginService.savePluginData("dae-proxy-widget", "groups", JSON.stringify(root.groups))
        pluginService.savePluginData("dae-proxy-widget", "nodes", JSON.stringify(root.nodePool))
        pluginService.savePluginData("dae-proxy-widget", "latencyMap", JSON.stringify(root.latencyMap))
    }

    function isNodeActive(name) {
        for (var i = 0; i < root.activeNodes.length; i++) { if (root.activeNodes[i] === name) return true }
        return false
    }

    function getProtocolColor(protocol) {
        if (protocol === "vless") return "#4fc3f7"
        if (protocol === "vmess") return "#ce93d8"
        if (protocol === "trojan") return "#a5d6a7"
        if (protocol === "ss" || protocol === "ssr") return "#80cbc4"
        if (protocol === "hysteria2" || protocol === "hy2") return "#f48fb1"
        if (protocol === "tuic") return "#ffe082"
        if (protocol === "juicity") return "#bcaaa4"
        return "#666"
    }
    function truncName(name, max) {
        if (!name) return "?"
        return name.length > max ? name.substring(0, max) + "..." : name
    }
    function nodeName(ni) { var nd = root.nodePool[ni]; return nd ? truncName(nd.name, 22) : "?" }
    function nodeLatText(ni) { var nd = root.nodePool[ni]; return nd ? root.latencyDisplay(nd.name) : "--- ms" }
    function nodeLatColor(ni) { var nd = root.nodePool[ni]; return nd ? root.latencyColor(nd.name) : Theme.surfaceVariantText }
    function nodeProtocol(ni) { var nd = root.nodePool[ni]; var p = nd ? nd.protocol : "?"; return p.length > 6 ? p.substring(0, 6) : p }
    function nodeIndicator(ni) {
        var nd = root.nodePool[ni]
        return (nd && root.isNodeActive(nd.name)) ? Theme.success : "#ff9800"
    }
    function nodeIndicatorFill(ni) {
        var nd = root.nodePool[ni]
        return (nd && root.isNodeActive(nd.name)) ? Theme.success : "transparent"
    }

    function gnColor(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return (nd && root.isNodeActive(nd.name)) ? Theme.success : "#ff9800"
    }
    function gnFill(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return (nd && root.isNodeActive(nd.name)) ? Theme.success : "transparent"
    }
    function gnProtocolColor(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return getProtocolColor(nd ? nd.protocol : "")
    }
    function gnProtocol(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        var p = nd ? nd.protocol : "?"; return p.length > 6 ? p.substring(0, 6) : p
    }
    function gnName(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return nd ? truncName(nd.name, 24) : "?"
    }
    function gnLatency(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return nd ? root.latencyDisplay(nd.name) : "--- ms"
    }
    function gnLatColor(gi, idx) {
        var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[idx] : null
        return nd ? root.latencyColor(nd.name) : Theme.surfaceVariantText
    }
    function subDisplay(idx) {
        var s = root.subscriptions[idx]
        if (!s) return ""
        var u = s.url || ""
        return (s.tag || "") + ": " + (u.length > 50 ? u.substring(0, 50) + "..." : u)
    }

    function addNodeToGroup(nodeName, groupName) {
        var node = null
        for (var p = 0; p < root.nodePool.length; p++) { if (root.nodePool[p].name === nodeName) { node = root.nodePool[p]; break } }
        if (!node) return
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            if (ng[g].name === groupName) {
                var ns = (ng[g].nodes || []).slice()
                for (var n = 0; n < ns.length; n++) { if (ns[n].name === node.name) { ToastService.showInfo("Already in " + groupName); return } }
                ns.push(node); ng[g].nodes = ns; root.groups = ng; persistData()
                return
            }
        }
    }
    function removeNodeFromGroup(groupName, nodeName) {
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            if (ng[g].name === groupName) {
                var ns = (ng[g].nodes || []).slice()
                for (var n = 0; n < ns.length; n++) { if (ns[n].name === nodeName) { ns.splice(n, 1); ng[g].nodes = ns; root.groups = ng; persistData(); return } }
                return
            }
        }
    }

    function createGroup() {
        var ng = root.groups.slice()
        var num = ng.length
        var name = "Group" + num
        for (var g = 0; g < ng.length; g++) { if (ng[g].name === name) { num++; name = "Group" + num; g = -1 } }
        ng.push({ name: name, nodes: [], isActive: false })
        root.groups = ng; persistData()
        ToastService.showInfo("Created: " + name)
    }
    function deleteGroup(groupName) {
        if (groupName === "proxy") { ToastService.showError("Cannot delete proxy group"); return }
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            if (ng[g].name === groupName) {
                if (ng[g].isActive) { ToastService.showError("Deactivate first"); return }
                ng.splice(g, 1); root.groups = ng; persistData(); return
            }
        }
    }

    function getActiveGroupName() {
        for (var g = 0; g < root.groups.length; g++) { if (root.groups[g].isActive) return root.groups[g].name }
        return "none"
    }
    function getActiveGroupNodes() {
        for (var g = 0; g < root.groups.length; g++) { if (root.groups[g].isActive) return root.groups[g].nodes || [] }
        return []
    }
    function latencyMs(name) {
        var m = root.latencyMap; if (!m || typeof m !== "object") return -1
        return typeof m[name] === "number" ? m[name] : -1
    }
    function latencyDisplay(name) {
        var l = latencyMs(name); return l >= 0 ? l + " ms" : "--- ms"
    }
    function latencyColor(name) {
        var l = latencyMs(name); if (l < 0) return Theme.surfaceVariantText
        if (l < 100) return Theme.success; if (l < 300) return "#ffc107"; return Theme.error
    }
    function testAllNodes() {
        root.testQueue = []
        for (var i = 0; i < root.nodePool.length; i++) {
            var nd = root.nodePool[i]
            if (nd.address) root.testQueue.push({ name: nd.name, host: nd.address, port: nd.port || "443" })
        }
        if (root.testQueue.length === 0) { ToastService.showError("No testable nodes"); return }
        ToastService.showInfo("Testing " + root.testQueue.length + " nodes...")
        processTestQueue()
    }
    function processTestQueue() {
        if (testProc.running) return
        if (root.testQueue.length === 0) { persistData(); return }
        var next = root.testQueue.shift()
        testProc.testNode = next.name
        testProc.command = ["curl", "-o", "/dev/null", "-s", "-w", "%{time_connect}", "--connect-timeout", "3", "http://" + next.host + ":" + next.port]
        testProc.running = true
    }

    property string userRouting: ""

    function writeDaeConfig() {
        var nodes = getActiveGroupNodes()
        var cfg = Engine.buildConfig(root.subscriptions, nodes, root.userRouting)
        configWriteProc.command = ["sh", "-c",
            "mkdir -p " + root.daeConfigDir + "/persist.d;" +
            "cat > " + root.daeConfigPath + " << 'DAEEOF'\n" + cfg + "DAEEOF\n" +
            "chmod 600 " + root.daeConfigPath + " && dae validate -c " + root.daeConfigPath + " && echo 'OK' || echo 'FAIL'"]
        configWriteProc.running = true
    }
    function activateGroup(groupName) {
        var ng = root.groups.slice()
        var active = []
        for (var g = 0; g < ng.length; g++) {
            if (ng[g].name === groupName) {
                ng[g].isActive = true
                var ns = ng[g].nodes || []
                for (var n = 0; n < ns.length; n++) active.push(ns[n].name)
            } else { ng[g].isActive = false }
        }
        root.groups = ng; root.activeNodes = active; persistData(); root.writeDaeConfig()
        ToastService.showInfo("Config writing & reloading...")
    }
    function deactivateGroup(groupName) {
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) { if (ng[g].name === groupName) { ng[g].isActive = false; break } }
        root.groups = ng; root.activeNodes = []; persistData(); root.writeDaeConfig()
        ToastService.showInfo("Group deactivated")
    }

    function loadFromCache() {
        root.nodePool = []
        ToastService.showInfo("Loading from persist.d...")
        configLoadProc.command = ["sh", "-c", "cat " + root.daeConfigDir + "/persist.d/*.sub 2>/dev/null"]
        configLoadProc.running = true
    }
    function updateSubscription() { root.writeDaeConfig() }
    function syncGroupNodes() {
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            var gns = (ng[g].nodes || []).slice()
            for (var n = 0; n < gns.length; n++) {
                for (var p = 0; p < root.nodePool.length; p++) {
                    if (root.nodePool[p].name === gns[n].name) { gns[n] = root.nodePool[p]; break }
                }
            }
            ng[g].nodes = gns
        }
        root.groups = ng; persistData()
    }

    function parseNodeLink(link) {
        var r = { link: link, tag: "", name: "", protocol: "", address: "", port: "" }
        var pm = link.match(/^([a-zA-Z0-9]+):\/\//); if (!pm) return r
        r.protocol = pm[1]
        var fm = link.match(/#(.+)$/)
        if (fm) {
            try { r.name = decodeURIComponent(fm[1]) } catch (e) { r.name = fm[1] }
            var parts = r.name.split("|"); var clean = []
            for (var p = 0; p < parts.length; p++) { if (parts[p] && parts[p].indexOf("L1") === -1 && parts[p].indexOf("x") === -1) clean.push(parts[p]) }
            r.name = clean.join("|") || r.name
        }
        var am = link.match(/@([^:?#]+):?(\d*)/); if (am) { r.address = am[1]; r.port = am[2] }
        if ((!r.name || r.name === "") && r.address) r.name = r.address
        if (!r.name || r.name === "") r.name = r.protocol.toUpperCase() + "_" + Math.random().toString(36).slice(2, 6)
        return r
    }
    function parseNodeLinks(raw) {
        var nodes = []; var seen = {}
        var lines = raw.split(/[\r\n]+/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim(); if (line.length < 15) continue
            var pm = line.match(/^([a-zA-Z0-9]+):\/\//); if (!pm) continue
            var proto = pm[1]
            var am = line.match(/@([^:?#]+):?(\d*)/); var addr = am ? am[1] : ""; var port = am ? am[2] : ""
            var fm = line.match(/#(.+)$/); var name = ""
            if (fm) {
                try { name = decodeURIComponent(fm[1]) } catch (e) { name = fm[1] }
                var parts = name.split("|"); var clean = []
                for (var p = 0; p < parts.length; p++) { if (parts[p] && parts[p].indexOf("L1") === -1 && parts[p].indexOf("x") === -1) clean.push(parts[p]) }
                name = clean.join("|") || name
            }
            if (!name && addr) name = addr
            if (!name) name = proto.toUpperCase()
            var key = name + "@" + addr; if (seen[key]) continue; seen[key] = true
            nodes.push({ link: line, tag: "", name: name, protocol: proto, address: addr, port: port, source: "wing.db" })
        }
        return nodes
    }
    function base64Decode(str) {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var out = ""; var i = 0; str = str.replace(/[^A-Za-z0-9\+\/\=]/g, "")
        while (i < str.length) {
            var a = chars.indexOf(str.charAt(i++)); var b = chars.indexOf(str.charAt(i++))
            var c = chars.indexOf(str.charAt(i++)); var d = chars.indexOf(str.charAt(i++))
            out += String.fromCharCode((a << 2) | (b >> 4))
            if (c !== 64) out += String.fromCharCode(((b & 15) << 4) | (c >> 2))
            if (d !== 64) out += String.fromCharCode(((c & 3) << 6) | d)
        }
        return out
    }
    function parseSubscriptionResponse(raw) {
        var nodes = []
        var text = raw.replace(/[\s\n\r\t]+/g, ""); if (!text) return nodes
        var decoded = root.base64Decode(text); if (!decoded) return nodes
        var lines = decoded.split(/[\r\n]+/)
        var schemes = ["ss://","vmess://","vless://","trojan://","hysteria2://","tuic://","juicity://","socks5://","http://","https://","ssr://","hy2://"]
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim(); if (line.length < 10 || line[0] === "#") continue
            for (var si = 0; si < schemes.length; si++) {
                if (line.indexOf(schemes[si]) === 0) { var p = root.parseNodeLink(line); p.source = "subscription"; p.subTag = "daed"; nodes.push(p); break }
            }
        }
        return nodes
    }

    function toggleProxy() { if (root.serviceRunning) { root.stopDaeService() } else { root.startDaeService() } }
    function startDaeService() { daeProcess.command = ["sudo", "systemctl", "start", "dae"]; root.pendingOperation = "start"; daeProcess.running = true; proxyStatus = "starting" }
    function stopDaeService() { daeProcess.command = ["sudo", "systemctl", "stop", "dae"]; root.pendingOperation = "stop"; daeProcess.running = true; proxyStatus = "stopping" }
    function checkServiceStatus() { statusCheckProcess.command = ["sudo", "systemctl", "is-active", "dae"]; statusCheckProcess.running = true }
    function updateProxyStatus(s) {
        proxyStatus = s
        if (s === "enabled") { root.proxyEnabled = true; root.serviceRunning = true }
        else if (s === "disabled") { root.proxyEnabled = false; root.serviceRunning = false }
        persistData()
    }

    Component.onCompleted: { DgopService.addRef(["network"]); checkServiceStatus() }
    Component.onDestruction: { DgopService.removeRef(["network"]) }

    Timer { id: networkMonitorTimer; interval: 1000; repeat: true; running: true; onTriggered: { root.networkRxRate = DgopService.networkRxRate; root.networkTxRate = DgopService.networkTxRate } }
    Timer { id: statusTimer; interval: 5000; repeat: true; running: true; onTriggered: root.checkServiceStatus() }

    Process {
        id: daeProcess; running: false
        onExited: (exitCode, exitStatus) => {
            if (root.pendingOperation === "stop") { if (exitCode === 0) { updateProxyStatus("disabled"); ToastService.showInfo("dae stopped") } else { updateProxyStatus("error"); ToastService.showError("Failed to stop dae") } }
            else { if (exitCode === 0) { updateProxyStatus("enabled"); ToastService.showInfo("dae started") } else { updateProxyStatus("error"); ToastService.showError("Failed to start dae") } }
            root.pendingOperation = ""
        }
    }
    Process {
        id: statusCheckProcess; running: false
        onExited: (exitCode, exitStatus) => { if (exitCode === 0) updateProxyStatus("enabled"); else updateProxyStatus("disabled") }
    }
    Process {
        id: configLoadProc; running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text
                if (!raw.trim()) { ToastService.showError("No cache. Click Update first."); return }
                var nodes = root.parseSubscriptionResponse(raw)
                if (nodes.length > 0) { root.nodePool = nodes; root.syncGroupNodes(); ToastService.showInfo("Loaded " + nodes.length + " nodes") }
                else { ToastService.showError("Cache empty (" + raw.length + " bytes)") }
            }
        }
    }
    Process {
        id: configWriteProc; running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.indexOf("OK") >= 0) { reloadProc.command = ["sudo", "systemctl", "restart", "dae"]; reloadProc.running = true }
                else { ToastService.showError("Config failed") }
            }
        }
    }
    Process {
        id: reloadProc; running: false
        onExited: (exitCode, exitStatus) => { if (exitCode === 0) { ToastService.showInfo("dae reloaded") } else { ToastService.showError("dae reload failed") } }
    }
    Process {
        id: testProc; running: false; property string testNode: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var t = parseFloat(text.trim()); if (isNaN(t) || t < 0) t = -1
                var m = root.latencyMap; if (typeof m !== "object") m = ({})
                m[testProc.testNode] = t >= 0 ? Math.round(t * 1000) : -1
                root.latencyMap = m
                if (root.testQueue.length > 0) processTestQueue()
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                id: pi; name: "network_check"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.serviceRunning ? "#ffc107" : Theme.widgetTextColor; anchors.verticalCenter: parent.verticalCenter
                transform: Scale { origin.x: pi.width / 2; xScale: root.serviceRunning ? -1 : 1 }
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            }
            Item { width: 70; height: parent.height; anchors.verticalCenter: parent.verticalCenter
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; spacing: 4
                    StyledText { text: "↓"; font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText); color: root.isHighSpeed() ? Theme.error : Theme.info }
                    StyledText { text: root.formatNetworkSpeed(root.networkRxRate); font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText); color: root.isHighSpeed() ? Theme.error : Theme.widgetTextColor; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideNone; wrapMode: Text.NoWrap }
                }
            }
            Item { width: 70; height: parent.height; anchors.verticalCenter: parent.verticalCenter
                Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; spacing: 4
                    StyledText { text: "↑"; font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText); color: Theme.error }
                    StyledText { text: root.formatNetworkSpeed(root.networkTxRate); font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText); color: Theme.widgetTextColor; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideNone; wrapMode: Text.NoWrap }
                }
            }
        }
    }
    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS; width: 44
            DankIcon {
                id: piv; name: "network_check"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.serviceRunning ? "#ffc107" : Theme.widgetTextColor; anchors.horizontalCenter: parent.horizontalCenter
                transform: Scale { origin.x: piv.width / 2; xScale: root.serviceRunning ? -1 : 1 }
                Behavior on color { ColorAnimation { duration: Theme.shortDuration } }
            }
            StyledText {
                text: { const r = root.networkRxRate; if (r < 1024) return r.toFixed(0); if (r < 1048576) return (r/1024).toFixed(0)+"K"; return (r/1048576).toFixed(0)+"M" }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.isHighSpeed() ? Theme.error : Theme.info; anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: { const r = root.networkTxRate; if (r < 1024) return r.toFixed(0); if (r < 1048576) return (r/1024).toFixed(0)+"K"; return (r/1048576).toFixed(0)+"M" }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.error; anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    Component {
        id: proxyPanelComponent
        Rectangle {
            id: proxyPanel
            color: "transparent"
            property bool showAddInput: false
            property bool subsExpanded: false
            property int currentTab: 0
            implicitHeight: col.implicitHeight

            Column {
                id: col; width: parent.width; spacing: Theme.spacingM

                Item { width: parent.width; height: Math.max(hl.implicitHeight, hr2.implicitHeight)
                    Row { id: hl; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
                        StyledText { text: "dae Proxy v3.1"; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Row { id: hr2; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Theme.spacingXS
                        DankToggle { anchors.verticalCenter: parent.verticalCenter; checked: root.serviceRunning || root.proxyStatus === "starting"; enabled: !daeProcess.running && root.proxyStatus !== "starting" && root.proxyStatus !== "stopping"; onToggled: root.toggleProxy() }
                        DankActionButton { iconName: "refresh"; iconColor: Theme.primary; buttonSize: Theme.iconSize + Theme.spacingS; anchors.verticalCenter: parent.verticalCenter; onClicked: root.testAllNodes() }
                        DankActionButton { iconName: "settings"; iconColor: Theme.surfaceText; buttonSize: Theme.iconSize + Theme.spacingS; anchors.verticalCenter: parent.verticalCenter; onClicked: { closePopout(); SettingsService.openPluginSettings("dae-proxy-widget") } }
                    }
                }

                Rectangle { width: parent.width; implicitHeight: ic2.implicitHeight + Theme.spacingM * 2; radius: Theme.cornerRadius; color: Theme.nestedSurface; border.color: Theme.outlineMedium; border.width: 1
                    Column { id: ic2; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM; spacing: Theme.spacingS
                        Row { spacing: Theme.spacingS
                            StyledText { text: "Status:"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: root.serviceRunning ? "● Running" : "○ Stopped"; font.pixelSize: Theme.fontSizeSmall; color: root.serviceRunning ? Theme.success : Theme.surfaceVariantText }
                        }
                        Row { spacing: Theme.spacingM
                            StyledText { text: "Subs:" + root.subscriptions.length; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: "Nodes:" + root.nodePool.length; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                            StyledText { text: "Active:" + root.getActiveGroupName(); font.pixelSize: Theme.fontSizeSmall; color: Theme.primary }
                        }
                        Row { width: parent.width; spacing: 4
                            DankButton { text: "↻ Update"; width: parent.width / 2 - 2; height: 28; onClicked: root.updateSubscription() }
                            DankButton { text: "Load Sub"; width: parent.width / 2 - 2; height: 28; onClicked: root.loadFromCache() }
                        }
                    }
                }

                Rectangle { width: parent.width; implicitHeight: subsCol2.implicitHeight + Theme.spacingM * 2; radius: Theme.cornerRadius; color: Theme.nestedSurface; border.color: Theme.outlineMedium; border.width: 1
                    Column { id: subsCol2; anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM; spacing: Theme.spacingS
                        DankButton { text: "+ Add Subscription"; width: parent.width; height: 32; onClicked: { proxyPanel.showAddInput = true; newSubUrl.text = "" } }
                        Row { width: parent.width; height: proxyPanel.showAddInput ? 30 : 0; visible: proxyPanel.showAddInput; spacing: 4
                            DankTextField { id: newSubUrl; width: parent.width - 34; height: 30; placeholderText: "https://..." }
                            DankButton { text: "✓"; width: 30; height: 30; onClicked: { var url = newSubUrl.text.trim(); if (!url) { ToastService.showError("Enter URL"); return } var s = root.subscriptions.slice(); s.push({ tag: "sub_" + (s.length+1), url: url }); root.subscriptions = s; root.persistData(); proxyPanel.showAddInput = false; root.writeDaeConfig(); ToastService.showInfo("Saved. Click Load Sub to fetch.") } }
                        }
                        Rectangle { width: parent.width; height: 1; color: Theme.outlineMedium; visible: root.subscriptions.length > 0 }
                        Row { width: parent.width; height: subMgrTitle2.implicitHeight; visible: root.subscriptions.length > 0; spacing: 4
                            StyledText { id: subMgrTitle2; text: (proxyPanel.subsExpanded ? "▾" : "▸") + " Subs (" + root.subscriptions.length + ")"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: proxyPanel.subsExpanded = !proxyPanel.subsExpanded }
                        }
                        Column { width: parent.width; visible: proxyPanel.subsExpanded && root.subscriptions.length > 0; spacing: 2
                            Repeater { model: root.subscriptions.length
                                delegate: Rectangle { width: subsCol2.width; height: 28; color: "transparent"
                                    property int idx: index
                                    Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.right: parent.right; spacing: 4
                                        StyledText { text: root.subDisplay(idx); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText; width: parent.width - 30; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                                        DankButton { text: "×"; width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter; onClicked: { var s = root.subscriptions.slice(); s.splice(idx, 1); root.subscriptions = s; root.persistData(); root.writeDaeConfig() } }
                                    }
                                }
                            }
                        }
                        StyledText { visible: root.subscriptions.length === 0 && !proxyPanel.showAddInput; text: "No subscriptions"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                    }
                }

                Rectangle { width: parent.width; height: 32; radius: Theme.cornerRadius; color: Theme.nestedSurface; border.color: Theme.outlineMedium; border.width: 1; clip: true
                    Row { anchors.fill: parent; anchors.margins: 3
                        Rectangle { width: parent.width / 2 - 6; height: parent.height; radius: Theme.cornerRadius; color: proxyPanel.currentTab === 0 ? Theme.primary : "transparent"
                            StyledText { anchors.centerIn: parent; text: "Nodes (" + root.nodePool.length + ")"; font.pixelSize: Theme.fontSizeSmall; color: proxyPanel.currentTab === 0 ? Theme.surfaceText : Theme.surfaceVariantText }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { proxyPanel.currentTab = 0; root.addTarget = "proxy" } }
                        }
                        Rectangle { width: parent.width / 2 - 6; height: parent.height; radius: Theme.cornerRadius; color: proxyPanel.currentTab === 1 ? Theme.primary : "transparent"
                            StyledText { anchors.centerIn: parent; text: "Groups (" + root.groups.length + ")"; font.pixelSize: Theme.fontSizeSmall; color: proxyPanel.currentTab === 1 ? Theme.surfaceText : Theme.surfaceVariantText }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { proxyPanel.currentTab = 1; root.addTarget = "proxy" } }
                        }
                    }
                }

                Rectangle { width: parent.width; height: proxyPanel.currentTab === 0 ? Math.min(nodesCol2.implicitHeight + Theme.spacingM * 2, 420) : 0; visible: proxyPanel.currentTab === 0; implicitHeight: height; radius: Theme.cornerRadius; color: Theme.nestedSurface; border.color: Theme.outlineMedium; border.width: 1; clip: true
                    Column { width: parent.width; anchors.top: parent.top; anchors.margins: Theme.spacingM
                        StyledText {
                            visible: root.addTarget !== "proxy"
                            text: "Pick → " + root.addTarget + "  [Done]"
                            font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.primary; width: parent.width - Theme.spacingM * 2; anchors.left: parent.left; anchors.leftMargin: Theme.spacingM
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.addTarget = "proxy"; proxyPanel.currentTab = 1 } }
                        }
                        Flickable { anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingM; height: Math.min(nodesCol2.implicitHeight, 380); contentHeight: nodesCol2.implicitHeight; clip: true; flickableDirection: Flickable.VerticalFlick; boundsBehavior: Flickable.DragAndOvershootBounds
                            Column { id: nodesCol2; width: parent.width; spacing: 2
                                StyledText { text: "Node Pool (" + root.nodePool.length + " nodes) — click ↻ to test"; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Medium; color: Theme.surfaceText }
                                Repeater { model: root.nodePool.length
                                    delegate: Rectangle { width: nodesCol2.width; height: 34; radius: 4; color: index % 2 ? "#0C808080" : "transparent"
                                        property int ni: index
                                        Row { anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8; anchors.right: parent.right; anchors.rightMargin: 8; spacing: 4
                                            Rectangle { width: 10; height: 10; radius: 5; anchors.verticalCenter: parent.verticalCenter; color: "transparent"; border.width: 2; border.color: root.nodeIndicator(ni)
                                                Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: root.nodeIndicatorFill(ni) }
                                            }
                                            Rectangle { width: 48; height: 18; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: root.getProtocolColor(root.nodePool[ni] ? root.nodePool[ni].protocol : "")
                                                StyledText { anchors.centerIn: parent; text: root.nodeProtocol(ni); font.pixelSize: 9; color: "#000" }
                                            }
                                            StyledText { text: root.nodeName(ni); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText; width: parent.width - 168; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                                            StyledText { text: root.nodeLatText(ni); font.pixelSize: Theme.fontSizeSmall; color: root.nodeLatColor(ni); width: 48; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                                            DankButton {
                                                text: "+"; width: 24; height: 24; anchors.verticalCenter: parent.verticalCenter
                                                onClicked: { var nd = root.nodePool[ni]; if (nd && nd.name) root.addNodeToGroup(nd.name, root.addTarget) }
                                            }
                                        }
                                    }
                                }
                                StyledText { visible: root.nodePool.length === 0; text: "No nodes. Click Update then Load Sub."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: proxyPanel.currentTab === 1 ? Math.max(60, groupsCol.implicitHeight + Theme.spacingM * 2) : 0; visible: proxyPanel.currentTab === 1; implicitHeight: height; radius: Theme.cornerRadius; color: Theme.nestedSurface; border.color: Theme.outlineMedium; border.width: 1; clip: true
                    Flickable { anchors.fill: parent; anchors.margins: Theme.spacingM; contentHeight: groupsCol.implicitHeight; clip: true; flickableDirection: Flickable.VerticalFlick; boundsBehavior: Flickable.DragAndOvershootBounds
                        Column { id: groupsCol; width: parent.width; spacing: 4
                            Repeater { model: root.groups.length
                                delegate: Rectangle { width: parent.width; implicitHeight: children[0].implicitHeight + Theme.spacingS * 2; radius: 6; border.color: Theme.outlineMedium; border.width: 1; color: "#0A808080"
                                    property int gi: index
                                    property string gname: root.groups[index] ? root.groups[index].name : "?"
                                    property bool gactive: root.groups[index] ? (root.groups[index].isActive || false) : false
                                    property int gcount: root.groups[index] && root.groups[index].nodes ? root.groups[index].nodes.length : 0
                                    property bool isDefault: gname === "proxy"
                                    property bool expanded: root.groups[index] ? (root.groups[index]._expanded !== false) : true

                                    Column { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Theme.spacingS; spacing: 4
                                        Item { width: parent.width; height: 30
                                            Row { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                                StyledText { text: expanded ? "▾" : "▸"; font.pixelSize: 12; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter
                                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { var ng = root.groups.slice(); ng[gi]._expanded = !expanded; root.groups = ng; root.persistData() } }
                                                }
                                                StyledText { text: isDefault ? "proxy (" + gcount + ")" : gname + " (" + gcount + ")"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                                                StyledText { text: gactive ? "● ACTIVE" : "○ idle"; font.pixelSize: Theme.fontSizeSmall; color: gactive ? Theme.success : Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                                            }
                                            Row { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4
                                                DankButton { text: "⊕"; width: 22; height: 22; visible: !isDefault; anchors.verticalCenter: parent.verticalCenter; onClicked: { var gn = root.groups[gi].name; root.addTarget = gn; proxyPanel.currentTab = 0 } }
                                                DankButton { text: "✕"; width: 22; height: 22; visible: !isDefault; anchors.verticalCenter: parent.verticalCenter; onClicked: root.deleteGroup(gname) }
                                                DankButton { text: gactive ? "●" : "▶"; width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter; onClicked: { if (gactive) { root.deactivateGroup(gname) } else { root.activateGroup(gname) } } }
                                            }
                                        }
                                        Column { width: parent.width; spacing: 2; visible: expanded
                                            Repeater { model: gcount
                                                Row { width: parent.width; height: 28; spacing: 4
                                                    Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter; color: "transparent"; border.width: 1.5; border.color: root.gnColor(gi, index)
                                                        Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 2; color: root.gnFill(gi, index) }
                                                    }
                                                    Rectangle { width: 42; height: 16; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: root.gnProtocolColor(gi, index)
                                                        StyledText { anchors.centerIn: parent; text: root.gnProtocol(gi, index); font.pixelSize: 9; color: "#000" }
                                                    }
                                                    StyledText { text: root.gnName(gi, index); font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceText; width: parent.width - 126; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter }
                                                    StyledText { text: root.gnLatency(gi, index); font.pixelSize: Theme.fontSizeSmall; color: root.gnLatColor(gi, index); width: 48; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                                                    StyledText { text: "✕"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter
                                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { var nd = root.groups[gi] && root.groups[gi].nodes ? root.groups[gi].nodes[index] : null; if (nd) root.removeNodeFromGroup(gname, nd.name) } }
                                                    }
                                                }
                                            }
                                            StyledText { visible: gcount === 0; text: "Empty. Use [+] in Nodes tab or [⊕] pick button."; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; horizontalAlignment: Text.AlignHCenter; width: parent.width }
                                        }
                                    }
                                }
                            }
                            DankButton { text: "+ New Group"; width: parent.width; height: 28; onClicked: root.createGroup() }
                        }
                    }
                }
            }
        }
    }
}
