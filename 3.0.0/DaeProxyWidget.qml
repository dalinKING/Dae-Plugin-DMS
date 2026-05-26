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

    popoutWidth: 380
    popoutContent: proxyPanelComponent
    pillRightClickAction: function() { root.toggleProxy() }

    onPluginServiceChanged: {
        if (!pluginService) return
        root.proxyEnabled = pluginService.loadPluginData("dae-proxy-widget", "proxyEnabled", false)
        root.serviceRunning = pluginService.loadPluginData("dae-proxy-widget", "serviceRunning", false)
        try { var s = pluginService.loadPluginData("dae-proxy-widget", "subscriptions", ""); if (s) root.subscriptions = JSON.parse(s) } catch (e) {}
        try { var g = pluginService.loadPluginData("dae-proxy-widget", "groups", ""); if (g) root.groups = JSON.parse(g) } catch (e) {}
        ensureProxyGroup()
    }

    function formatNetworkSpeed(b) {
        if (b < 1024) return b.toFixed(0) + " B/s"
        if (b < 1048576) return (b / 1024).toFixed(1) + " KB/s"
        if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB/s"
        return (b / 1073741824).toFixed(1) + " GB/s"
    }
    function isHighSpeed() {
        return root.networkRxRate > 2097152 || root.networkTxRate > 2097152
    }
    function ensureProxyGroup() {
        for (var i = 0; i < root.groups.length; i++) {
            if (root.groups[i].name === "proxy") return
        }
        var ng = root.groups.slice()
        ng.unshift({ name: "proxy", nodes: [], isActive: false })
        root.groups = ng
    }
    function persistData() {
        if (!pluginService) return
        root.ensureProxyGroup()
        pluginService.savePluginData("dae-proxy-widget", "proxyEnabled", root.proxyEnabled)
        pluginService.savePluginData("dae-proxy-widget", "serviceRunning", root.serviceRunning)
        pluginService.savePluginData("dae-proxy-widget", "subscriptions", JSON.stringify(root.subscriptions))
        pluginService.savePluginData("dae-proxy-widget", "groups", JSON.stringify(root.groups))
    }
    function isNodeActive(name) {
        for (var i = 0; i < root.activeNodes.length; i++) {
            if (root.activeNodes[i] === name) return true
        }
        return false
    }
    function toggleSingleNode(nodeName) {
        var an = root.activeNodes.slice()
        var found = -1
        for (var i = 0; i < an.length; i++) {
            if (an[i] === nodeName) { found = i; break }
        }
        if (found >= 0) {
            an.splice(found, 1)
        } else {
            an = [nodeName]
        }
        root.activeNodes = an
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) { ng[g].isActive = false }
        root.groups = ng
        persistData()
        ToastService.showInfo(found >= 0 ? "Node deactivated" : "Active: " + nodeName)
    }
    function addNodeToGroup(ni, groupName) {
        var nd = root.nodePool[ni]
        if (!nd || !nd.name) return
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            if (ng[g].name === groupName) {
                var ns = (ng[g].nodes || []).slice()
                var found = false
                for (var n = 0; n < ns.length; n++) {
                    if (ns[n].name === nd.name) { found = true; break }
                }
                if (!found) { ns.push(nd); ng[g].nodes = ns }
                break
            }
        }
        root.groups = ng
        persistData()
    }
    property string userRouting: ""

    function generateDaeConfig() {
        var g0 = root.groups[0]
        var nodes = (g0 && g0.nodes) ? g0.nodes : []
        return Engine.buildConfig(root.subscriptions, nodes, root.userRouting)
    }
    function writeDaeConfig() {
        var g0 = root.groups[0]
        var nodes = (g0 && g0.nodes) ? g0.nodes : []
        var cfg = Engine.buildConfig(root.subscriptions, nodes, root.userRouting)
        configWriteProc.command = ["sh", "-c",
            "mkdir -p /home/dalin/.config/dae/persist.d;" +
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
                for (var n = 0; n < ns.length; n++) { active.push(ns[n].name) }
            } else {
                ng[g].isActive = false
            }
        }
        root.groups = ng
        root.activeNodes = active
        persistData()
        root.writeDaeConfig()
        ToastService.showInfo("Writing config & reloading dae...")
    }

    function loadFromCache() {
        root.nodePool = []
        ToastService.showInfo("Loading from persist.d...")
        configLoadProc.running = false
        configLoadProc.command = ["sh", "-c", "cat /home/dalin/.config/dae/persist.d/*.sub 2>/dev/null"]
        configLoadProc.running = true
    }
    function updateSubscription() {
        root.writeDaeConfig()
    }
    function syncGroupNodes() {
        var ng = root.groups.slice()
        for (var g = 0; g < ng.length; g++) {
            var gns = (ng[g].nodes || []).slice()
            for (var n = 0; n < gns.length; n++) {
                for (var p = 0; p < root.nodePool.length; p++) {
                    if (root.nodePool[p].name === gns[n].name) {
                        gns[n] = root.nodePool[p]
                        break
                    }
                }
            }
            ng[g].nodes = gns
        }
        root.groups = ng
        persistData()
    }
    function parseNodeLink(link) {
        var r = { link: link, tag: "", name: "", protocol: "", address: "", port: "" }
        var pm = link.match(/^([a-zA-Z0-9]+):\/\//)
        if (!pm) return r
        r.protocol = pm[1]
        var fm = link.match(/#(.+)$/)
        if (fm) {
            try { r.name = decodeURIComponent(fm[1]) } catch (e) { r.name = fm[1] }
            var parts = r.name.split("|")
            var clean = []
            for (var p = 0; p < parts.length; p++) {
                if (parts[p] && parts[p].indexOf("L1") === -1 && parts[p].indexOf("x") === -1)
                    clean.push(parts[p])
            }
            r.name = clean.join("|") || r.name
        }
        var am = link.match(/@([^:?#]+):?(\d*)/)
        if (am) { r.address = am[1]; r.port = am[2] }
        if ((!r.name || r.name === "") && r.address) r.name = r.address
        if (!r.name || r.name === "") r.name = r.protocol.toUpperCase() + "_" + Math.random().toString(36).slice(2, 6)
        return r
    }
    function parseConfigNodes(raw) {
        var nodes = []
        var lines = raw.split(/[\r\n]+/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            var m = line.match(/^\s*(\w+)\s*:\s*'([^']+)'/)
            if (!m) continue
            var tag = m[1]
            var link = m[2]
            var nd = root.parseNodeLink(link)
            nd._tag = tag
            nd.source = "config"
            nodes.push(nd)
        }
        return nodes
    }
    function parseNodeLinks(raw) {
        var nodes = []
        var seen = {}
        var lines = raw.split(/[\r\n]+/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.length < 15) continue
            var pm = line.match(/^([a-zA-Z0-9]+):\/\//)
            if (!pm) continue
            var proto = pm[1]
            var am = line.match(/@([^:?#]+):?(\d*)/)
            var addr = am ? am[1] : ""
            var port = am ? am[2] : ""
            var fm = line.match(/#(.+)$/)
            var name = ""
            if (fm) {
                try { name = decodeURIComponent(fm[1]) } catch (e) { name = fm[1] }
                var parts = name.split("|")
                var clean = []
                for (var p = 0; p < parts.length; p++) {
                    if (parts[p] && parts[p].indexOf("L1") === -1 && parts[p].indexOf("x") === -1)
                        clean.push(parts[p])
                }
                name = clean.join("|") || name
            }
            if (!name && addr) name = addr
            if (!name) name = proto.toUpperCase()
            var key = name + "@" + addr
            if (seen[key]) continue
            seen[key] = true
            nodes.push({
                link: line,
                tag: "",
                name: name,
                protocol: proto,
                address: addr,
                port: port,
                source: "wing.db"
            })
        }
        return nodes
    }
    function base64Decode(str) {
        var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        var out = ""
        var i = 0
        str = str.replace(/[^A-Za-z0-9\+\/\=]/g, "")
        while (i < str.length) {
            var a = chars.indexOf(str.charAt(i++))
            var b = chars.indexOf(str.charAt(i++))
            var c = chars.indexOf(str.charAt(i++))
            var d = chars.indexOf(str.charAt(i++))
            out += String.fromCharCode((a << 2) | (b >> 4))
            if (c !== 64) out += String.fromCharCode(((b & 15) << 4) | (c >> 2))
            if (d !== 64) out += String.fromCharCode(((c & 3) << 6) | d)
        }
        return out
    }
    function parseSubscriptionResponse(raw) {
        var nodes = []
        var text = raw.replace(/[\s\n\r\t]+/g, "")
        if (!text) return nodes
        var decoded = root.base64Decode(text)
        if (!decoded) return nodes
        var lines = decoded.split(/[\r\n]+/)
        var schemes = ["ss://","vmess://","vless://","trojan://","hysteria2://","tuic://","juicity://","socks5://","http://","https://","ssr://","hy2://"]
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.length < 10 || line[0] === "#") continue
            for (var si = 0; si < schemes.length; si++) {
                if (line.indexOf(schemes[si]) === 0) {
                    var p = root.parseNodeLink(line)
                    p.source = "subscription"
                    p.subTag = "daed"
                    nodes.push(p)
                    break
                }
            }
        }
        return nodes
    }
    function parseDaeConfigSubs(raw) {
        var subs = []
        var inSub = false
        var lines = raw.split(/[\r\n]+/)
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line.indexOf("subscription") === 0 && line.indexOf("{") > 0) { inSub = true; continue }
            if (inSub && line.indexOf("}") === 0) { inSub = false; continue }
            if (inSub && line.length > 10) {
                var m = line.match(/^\s*(\w+)?\s*:\s*'([^']+)'/)
                if (m) subs.push({ tag: m[1] || "", url: m[2] })
            }
        }
        return subs
    }

    function toggleProxy() { if (proxyEnabled) { stopDaeService() } else { startDaeService() } }
    function startDaeService() {
        daeProcess.command = ["sudo", "systemctl", "start", "dae"]
        root.pendingOperation = "start"
        daeProcess.running = true
        proxyStatus = "starting"
    }
    function stopDaeService() {
        daeProcess.command = ["sudo", "systemctl", "stop", "dae"]
        root.pendingOperation = "stop"
        daeProcess.running = true
        proxyStatus = "stopping"
    }
    function checkServiceStatus() {
        statusCheckProcess.command = ["sudo", "systemctl", "is-active", "dae"]
        statusCheckProcess.running = true
    }
    function updateProxyStatus(s) {
        proxyStatus = s
        if (s === "enabled") { root.proxyEnabled = true; root.serviceRunning = true }
        else if (s === "disabled") { root.proxyEnabled = false; root.serviceRunning = false }
        persistData()
    }

    Component.onCompleted: { DgopService.addRef(["network"]); checkServiceStatus() }
    Component.onDestruction: { DgopService.removeRef(["network"]) }

    Timer {
        id: networkMonitorTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.networkRxRate = DgopService.networkRxRate
            root.networkTxRate = DgopService.networkTxRate
        }
    }
    Timer {
        id: statusTimer
        interval: 5000
        repeat: true
        running: root.proxyEnabled
        onTriggered: root.checkServiceStatus()
    }
    Process {
        id: daeProcess
        running: false
        onExited: (exitCode, exitStatus) => {
            if (root.pendingOperation === "stop") {
                if (exitCode === 0) { updateProxyStatus("disabled"); ToastService.showInfo("dae stopped") }
                else { updateProxyStatus("error"); ToastService.showError("Failed to stop dae") }
            } else {
                if (exitCode === 0) { updateProxyStatus("enabled"); ToastService.showInfo("dae started") }
                else { updateProxyStatus("error"); ToastService.showError("Failed to start dae") }
            }
            root.pendingOperation = ""
        }
    }
    Process {
        id: statusCheckProcess
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) updateProxyStatus("enabled")
            else updateProxyStatus("disabled")
        }
    }
    Process {
        id: configLoadProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = text
                if (!raw.trim()) {
                    ToastService.showError("No cache. Click Update first to generate subscription cache.")
                    return
                }
                var nodes = root.parseSubscriptionResponse(raw)
                if (nodes.length > 0) {
                    root.nodePool = nodes
                    root.syncGroupNodes()
                    ToastService.showInfo("Loaded " + nodes.length + " nodes from cache")
                } else {
                    ToastService.showError("Cache empty or unreadable (" + raw.length + " bytes)")
                }
            }
        }
    }
    Process {
        id: configWriteProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var out = text
                if (out.indexOf("OK") >= 0) {
                    reloadProc.command = ["sudo", "systemctl", "restart", "dae"]
                    reloadProc.running = true
                } else {
                    ToastService.showError("Config failed — need NOPASSWD for cp & dae reload")
                }
            }
        }
    }
    Process {
        id: reloadProc
        running: false
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                ToastService.showInfo("dae reloaded — proxy group active")
            } else {
                ToastService.showError("dae reload failed — check config syntax")
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS
            DankIcon {
                id: pi
                name: "network_check"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.proxyStatus === "enabled" ? "#ffc107" : Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
                transform: Scale {
                    origin.x: pi.width / 2
                    xScale: root.proxyStatus === "enabled" ? -1 : 1
                }
                Behavior on color {
                    ColorAnimation { duration: Theme.shortDuration }
                }
            }
            Item {
                width: 70
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 4
                    StyledText {
                        text: "↓"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.isHighSpeed() ? Theme.error : Theme.info
                    }
                    StyledText {
                        text: root.formatNetworkSpeed(root.networkRxRate)
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: root.isHighSpeed() ? Theme.error : Theme.widgetTextColor
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideNone
                        wrapMode: Text.NoWrap
                    }
                }
            }
            Item {
                width: 70
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    spacing: 4
                    StyledText {
                        text: "↑"
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.error
                    }
                    StyledText {
                        text: root.formatNetworkSpeed(root.networkTxRate)
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        color: Theme.widgetTextColor
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideNone
                        wrapMode: Text.NoWrap
                    }
                }
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            width: 44
            DankIcon {
                id: piv
                name: "network_check"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.proxyStatus === "enabled" ? "#ffc107" : Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
                transform: Scale {
                    origin.x: piv.width / 2
                    xScale: root.proxyStatus === "enabled" ? -1 : 1
                }
                Behavior on color {
                    ColorAnimation { duration: Theme.shortDuration }
                }
            }
            StyledText {
                text: {
                    const rate = root.networkRxRate
                    if (rate < 1024) return rate.toFixed(0)
                    if (rate < 1024 * 1024) return (rate / 1024).toFixed(0) + "K"
                    return (rate / (1024 * 1024)).toFixed(0) + "M"
                }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.isHighSpeed() ? Theme.error : Theme.info
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: {
                    const rate = root.networkTxRate
                    if (rate < 1024) return rate.toFixed(0)
                    if (rate < 1024 * 1024) return (rate / 1024).toFixed(0) + "K"
                    return (rate / (1024 * 1024)).toFixed(0) + "M"
                }
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: Theme.error
                anchors.horizontalCenter: parent.horizontalCenter
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
                id: col
                width: parent.width
                spacing: Theme.spacingM

                Item {
                    width: parent.width
                    height: Math.max(hr.implicitHeight, ar.implicitHeight)
                    Row {
                        id: hr
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        StyledText {
                            text: "Dae Proxy V3.0"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Row {
                        id: ar
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        DankToggle {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.proxyStatus === "enabled" || root.proxyStatus === "starting"
                            enabled: !daeProcess.running
                            onToggled: root.toggleProxy()
                        }
                        DankActionButton {
                            iconName: "info"
                            iconColor: Theme.primary
                            buttonSize: Theme.iconSize + Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        DankActionButton {
                            iconName: "settings"
                            iconColor: Theme.surfaceText
                            buttonSize: Theme.iconSize + Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                closePopout()
                                SettingsService.openPluginSettings("dae-proxy-widget")
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: ic.implicitHeight + Theme.spacingM * 2
                    implicitHeight: height
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.color: Theme.outlineMedium
                    border.width: 1
                    Column {
                        id: ic
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS
                        Row {
                            spacing: Theme.spacingS
                            StyledText {
                                text: "Status:"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: root.proxyStatus === "enabled" ? "● Running" : "○ Stopped"
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.proxyStatus === "enabled" ? Theme.success : Theme.surfaceVariantText
                            }
                        }
                        Row {
                            spacing: Theme.spacingM
                            StyledText {
                                text: "Subs: " + root.subscriptions.length
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: "Nodes: " + root.nodePool.length
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: "Proxy: "
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                            StyledText {
                                text: "↓ " + root.formatNetworkSpeed(root.networkRxRate)
                                font.pixelSize: Theme.fontSizeSmall
                                color: root.isHighSpeed() ? Theme.error : Theme.info
                            }
                        }
                        Row {
                            width: parent.width
                            spacing: 4
                            DankButton {
                                text: "↻ Update"
                                width: parent.width / 2 - 2
                                height: 28
                                onClicked: root.updateSubscription()
                            }
                            DankButton {
                                text: "Load_Sub"
                                width: parent.width / 2 - 2
                                height: 28
                                onClicked: root.loadFromCache()
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: subsCol.implicitHeight + Theme.spacingM * 2
                    implicitHeight: height
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.color: Theme.outlineMedium
                    border.width: 1
                    Column {
                        id: subsCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS
                        DankButton {
                            text: "+ Add Subscription"
                            width: parent.width
                            height: 32
                            onClicked: {
                                proxyPanel.showAddInput = true
                                newSubUrl.text = ""
                            }
                        }
                        Row {
                            width: parent.width
                            height: proxyPanel.showAddInput ? 30 : 0
                            visible: proxyPanel.showAddInput
                            spacing: 4
                            DankTextField {
                                id: newSubUrl
                                width: parent.width - 34
                                height: 30
                                placeholderText: "https://..."
                            }
                            DankButton {
                                text: "✓"
                                width: 30
                                height: 30
                                onClicked: {
                                    var url = newSubUrl.text.trim()
                                    if (!url) {
                                        ToastService.showError("Enter a subscription URL")
                                        return
                                    }
                                    var s = root.subscriptions.slice()
                                    s.push({ tag: "sub_" + (s.length + 1), url: url })
                                    root.subscriptions = s
                                    root.persistData()
                                    proxyPanel.showAddInput = false
                                    root.writeDaeConfig()
                                    ToastService.showInfo("Subscription saved & dae restarting. Click [Load] to fetch nodes.")
                                }
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Theme.outlineMedium
                            visible: root.subscriptions.length > 0
                        }
                        Item {
                            width: parent.width
                            height: subMgrTitle.implicitHeight
                            visible: root.subscriptions.length > 0
                            StyledText {
                                id: subMgrTitle
                                text: (proxyPanel.subsExpanded ? "▾" : "▸") + " Subscription Manager (" + root.subscriptions.length + ")"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { proxyPanel.subsExpanded = !proxyPanel.subsExpanded }
                            }
                        }
                        Column {
                            width: parent.width
                            visible: proxyPanel.subsExpanded && root.subscriptions.length > 0
                            spacing: 2
                            Repeater {
                                model: root.subscriptions.length
                                delegate: subsDel
                            }
                        }
                        StyledText {
                            visible: root.subscriptions.length === 0 && !proxyPanel.showAddInput
                            text: "No subscriptions. [+ Add] a URL, then [↻ Update]."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 32
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.color: Theme.outlineMedium
                    border.width: 1
                    clip: true
                    Row {
                        anchors.fill: parent
                        Rectangle {
                            width: parent.width / 2 - 6
                            height: parent.height
                            radius: Theme.cornerRadius
                            color: proxyPanel.currentTab === 0 ? Theme.primary : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "Nodes (" + root.nodePool.length + ")"
                                font.pixelSize: Theme.fontSizeSmall
                                color: proxyPanel.currentTab === 0 ? Theme.surfaceText : Theme.surfaceVariantText
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: proxyPanel.currentTab = 0
                            }
                        }
                        Rectangle {
                            width: parent.width / 2 - 6
                            height: parent.height
                            radius: Theme.cornerRadius
                            color: proxyPanel.currentTab === 1 ? Theme.primary : "transparent"
                            StyledText {
                                anchors.centerIn: parent
                                text: "Group (" + root.groups[0].nodes.length  + ")"
                                font.pixelSize: Theme.fontSizeSmall
                                color: proxyPanel.currentTab === 1 ? Theme.surfaceText : Theme.surfaceVariantText
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: proxyPanel.currentTab = 1
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: proxyPanel.currentTab === 0 ? Math.min(nodesCol.implicitHeight + Theme.spacingM * 2, 380) : 0
                    visible: proxyPanel.currentTab === 0
                    implicitHeight: height
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.color: Theme.outlineMedium
                    border.width: 1
                    clip: true
                    Flickable {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        contentHeight: nodesCol.implicitHeight
                        clip: true
                        flickableDirection: Flickable.VerticalFlick
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        Column {
                            id: nodesCol
                            width: parent.width
                            spacing: 2
                            StyledText {
                                text: "Node Pool (" + root.nodePool.length + " nodes)"
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            Repeater {
                                model: root.nodePool.length
                                delegate: nodeDel
                            }
                            StyledText {
                                visible: root.nodePool.length === 0
                                text: "No nodes. Click [↻ Update] then [Load]."
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                horizontalAlignment: Text.AlignHCenter
                                width: parent.width
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: proxyPanel.currentTab === 1 ? Math.max(80, 44 + nodeRows.count * 28 + Theme.spacingM * 2) : 0
                    visible: proxyPanel.currentTab === 1
                    implicitHeight: height
                    radius: Theme.cornerRadius
                    color: Theme.nestedSurface
                    border.color: Theme.outlineMedium
                    border.width: 1
                    clip: true
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: 4
                        Item {
                            width: parent.width
                            height: 38
                            StyledText {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    var grp = root.groups[0]
                                    var cnt = (grp && grp.nodes) ? grp.nodes.length : 0
                                    return "proxy (" + cnt + ")"
                                }
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                anchors.left: parent.left
                                anchors.leftMargin: 120
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.groups[0] && root.groups[0].isActive) ? "● ACTIVE" : "○ idle"
                                font.pixelSize: Theme.fontSizeSmall
                                color: (root.groups[0] && root.groups[0].isActive) ? Theme.success : Theme.surfaceVariantText
                            }
                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8
                                visible: (root.groups[0] && root.groups[0].nodes && root.groups[0].nodes.length > 0)
                                StyledText {
                                    text: "✗"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: (root.groups[0] && !root.groups[0].isActive) ? Theme.error : Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var grp = root.groups[0]
                                            if (!grp) return
                                            if (grp.isActive) {
                                                var ng = root.groups.slice()
                                                ng[0].isActive = false
                                                root.groups = ng
                                                root.activeNodes = []
                                                root.persistData()
                                                ToastService.showInfo("Deactivated. Click ✗ again to clear.")
                                            } else {
                                                var ng2 = root.groups.slice()
                                                ng2[0].nodes = []
                                                ng2[0].isActive = false
                                                root.groups = ng2
                                                root.activeNodes = []
                                                root.persistData()
                                                ToastService.showInfo("Group cleared")
                                            }
                                        }
                                    }
                                }
                                Item { width: 14; height: 1 }
                                DankButton {
                                    text: "✓"
                                    width: 22
                                    height: 22
                                    onClicked: root.activateGroup("proxy")
                                }
                            }
                        }
                        Column {
                            id: nodeRows
                            width: parent.width
                            spacing: 2
                            property int count: (root.groups[0] && root.groups[0].nodes) ? root.groups[0].nodes.length : 0
                            Repeater {
                                model: (root.groups[0] && root.groups[0].nodes) ? root.groups[0].nodes.length : 0
                                Row {
                                    width: parent.width
                                    height: 26
                                    spacing: 4
                                    Rectangle {
                                        width: 6; height: 6; radius: 3
                                        color: "transparent"; border.width: 1.5
                                        border.color: {
                                            var nd = (root.groups[0] && root.groups[0].nodes) ? root.groups[0].nodes[index] : null
                                            return (nd && root.isNodeActive(nd.name)) ? Theme.success : "#ff9800"
                                        }
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: {
                                            var nd = (root.groups[0] && root.groups[0].nodes) ? root.groups[0].nodes[index] : null
                                            var n = (nd && nd.name) ? nd.name : "?"
                                            if (n.length > 30) n = n.substring(0, 30) + "..."
                                            return n
                                        }
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        width: parent.width - 84
                                        elide: Text.ElideRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "--- ms    "
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        width: 48
                                        horizontalAlignment: Text.AlignRight
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    StyledText {
                                        text: "✗"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        anchors.verticalCenter: parent.verticalCenter
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var ng = root.groups.slice()
                                                var g0 = ng[0]
                                                if (g0 && g0.nodes) {
                                                    var ns = g0.nodes.slice()
                                                    ns.splice(index, 1)
                                                    g0.nodes = ns
                                                    ng[0] = g0
                                                    root.groups = ng
                                                    root.persistData()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        StyledText {
                            visible: !root.groups[0] || !root.groups[0].nodes || root.groups[0].nodes.length === 0
                            text: "Empty. Use [+] in Nodes tab."
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                        }
                    }
                }
            }

            Component {
                id: subsDel
                Row {
                    width: subsCol.width
                    height: 28
                    spacing: 4
                    property int idx: index
                    StyledText {
                        text: {
                            var s = root.subscriptions[idx]
                            if (!s) return ""
                            var u = s.url || ""
                            if (u.length > 50) u = u.substring(0, 50) + "..."
                            return (s.tag || "") + ": " + u
                        }
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        width: parent.width - 30
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    DankButton {
                        text: "×"
                        width: 24
                        height: 24
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            var s = root.subscriptions.slice()
                            s.splice(idx, 1)
                            root.subscriptions = s
                            root.persistData()
                            root.writeDaeConfig()
                        }
                    }
                }
            }

            Component {
                id: nodeDel
                Rectangle {
                    width: nodesCol.width
                    height: 32
                    radius: 4
                    color: index % 2 ? Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.05) : "transparent"
                    property int ni: index
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        spacing: 4
                        Item {
                            width: 10
                            height: parent.height
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                color: "transparent"
                                border.width: 2
                                border.color: {
                                    var nd = root.nodePool[ni]
                                    return (nd && root.isNodeActive(nd.name)) ? Theme.success : "#ff9800"
                                }
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: {
                                        var nd = root.nodePool[ni]
                                        return (nd && root.isNodeActive(nd.name)) ? Theme.success : "transparent"
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var nd = root.nodePool[ni]
                                    if (nd && nd.name) root.toggleSingleNode(nd.name)
                                }
                            }
                        }
                        StyledText {
                            text: {
                                var nd = root.nodePool[ni]
                                if (!nd) return "?"
                                var n = nd.name || "?"
                                if (n.length > 24) n = n.substring(0, 24) + "..."
                                return n
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            width: parent.width - 94
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var nd = root.nodePool[ni]
                                    if (nd && nd.name) root.toggleSingleNode(nd.name)
                                }
                            }
                        }
                        StyledText {
                            text: "--- ms    "
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: 48
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        DankButton {
                            text: "+"
                            width: 24
                            height: 24
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: {
                                root.addNodeToGroup(ni, "proxy")
                                ToastService.showInfo("Added to proxy")
                            }
                        }
                    }
                }
            }
        }
    }
}
