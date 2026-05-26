// dae Config Engine — separate from UI
// Handles: tag sanitization, config generation, config merging, file I/O

function sanitizeTag(name) {
    // Convert node names to valid dae identifiers: alphanumeric + underscore only
    var tag = name.replace(/[^a-zA-Z0-9_]/g, "_")
    tag = tag.replace(/_+/g, "_").replace(/^_|_$/g, "")
    if (!tag || tag.length === 0) tag = "node_0"
    if (/^\d/.test(tag)) tag = "n_" + tag
    return tag.toLowerCase()
}

function generateNodeSection(nodes) {
    if (!nodes || nodes.length === 0) return ""
    var s = "node {\n"
    for (var i = 0; i < nodes.length; i++) {
        var nd = nodes[i]
        var tag = sanitizeTag(nd.name || ("node_" + i))
        nd._tag = tag
        if (nd.link) s += "    " + tag + ": '" + nd.link + "'\n"
    }
    s += "}\n\n"
    return s
}

function generateGroupSection(nodes) {
    if (!nodes || nodes.length === 0) return ""
    var s = "group {\n"
    s += "    proxy {\n"
    for (var i = 0; i < nodes.length; i++) {
        var tag = nodes[i]._tag || sanitizeTag(nodes[i].name || ("node_" + i))
        s += "        filter: name(\"" + tag + "\")\n"
    }
    s += "        policy: min_moving_avg\n"
    s += "    }\n"
    s += "}\n\n"
    return s
}

function generateGlobalSection() {
    return "global {\n" +
        "    tproxy_port: 12345\n" +
        "    tproxy_port_protect: true\n" +
        "    log_level: info\n" +
        "    wan_interface: auto\n" +
        "    auto_config_kernel_parameter: true\n" +
        "    tcp_check_url: 'http://cp.cloudflare.com,1.1.1.1,2606:4700:4700::1111'\n" +
        "    tcp_check_http_method: HEAD\n" +
        "    udp_check_dns: 'dns.google:53,8.8.8.8,2001:4860:4860::8888'\n" +
        "    check_interval: 300s\n" +
        "    check_tolerance: 100ms\n" +
        "    dial_mode: ip\n" +
        "    tls_implementation: tls\n" +
        "    mptcp: false\n" +
        "    tls_fragment: false\n" +
        "}\n\n"
}

function generateSubscriptionSection(subs) {
    if (!subs || subs.length === 0) return ""
    var s = "subscription {\n"
    for (var i = 0; i < subs.length; i++) {
        var sub = subs[i]
        if (sub.url) s += "    " + (sub.tag || "sub_" + i) + ": '" + sub.url + "'\n"
    }
    s += "}\n\n"
    return s
}

function generateDnsSection() {
    return "dns {\n" +
        "    upstream {\n" +
        "        alidns: 'udp://223.5.5.5:53'\n" +
        "    }\n" +
        "    routing {\n" +
        "        request {\n" +
        "            fallback: alidns\n" +
        "        }\n" +
        "    }\n" +
        "}\n\n"
}

function generateRoutingSection() {
    return "routing {\n" +
        "    pname(systemd-resolved, dnsmasq) -> must_direct\n" +
        "    dip(geoip:private) -> direct\n" +
        "    dip(geoip:cn) -> direct\n" +
        "    domain(geosite:cn) -> direct\n" +
        "    fallback: proxy\n" +
        "}\n"
}

// Merge: replace sections we manage, preserve user's custom sections
// We manage: node, group. We preserve: routing (user's custom rules)
function mergeConfig(userRouting, nodes, subs) {
    var c = generateGlobalSection()
    c += generateSubscriptionSection(subs)
    c += generateNodeSection(nodes)
    c += generateGroupSection(nodes)
    c += generateDnsSection()
    // Use user's routing if provided, otherwise default
    if (userRouting && userRouting.trim()) {
        c += userRouting.trim() + "\n"
    } else {
        c += generateRoutingSection()
    }
    return c
}

// Full config from plugin state — preserves existing routing from dae config
function buildConfig(subs, nodes, existingRouting) {
    return mergeConfig(existingRouting, nodes, subs)
}
