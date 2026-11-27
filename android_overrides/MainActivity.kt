// Copied over the generated MainActivity.kt by the GitHub Actions workflow.
// The `package` line is rewritten automatically to match the generated project.
package com.modemzaid.modem_zaid

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "modemzaid/wifi_network"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "getWifiInfo" -> {
                            val bind = call.argument<Boolean>("bind") ?: true
                            result.success(readWifiInfo(bind))
                        }
                        "unbind" -> {
                            connectivity().bindProcessToNetwork(null)
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("WIFI_NET", e.message, null)
                }
            }
    }

    private fun connectivity(): ConnectivityManager =
        applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    @Suppress("DEPRECATION")
    private fun findWifiNetwork(cm: ConnectivityManager): Network? {
        for (net in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(net) ?: continue
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return net
        }
        return null
    }

    private fun intToIp(v: Int): String =
        "${v and 0xff}.${(v shr 8) and 0xff}.${(v shr 16) and 0xff}.${(v shr 24) and 0xff}"

    private fun readWifiInfo(bind: Boolean): Map<String, Any?> {
        val cm = connectivity()
        val out = HashMap<String, Any?>()
        val net = findWifiNetwork(cm)
        if (net == null) {
            out["connected"] = false
            return out
        }
        out["connected"] = true

        var gateway: String? = null
        var localIp: String? = null
        val dns = ArrayList<String>()
        val lp = cm.getLinkProperties(net)
        if (lp != null) {
            for (route in lp.routes) {
                val gw = route.gateway
                if (route.isDefaultRoute && gw is Inet4Address) {
                    val host = gw.hostAddress
                    if (host != null && host != "0.0.0.0") {
                        gateway = host
                        break
                    }
                }
            }
            for (la in lp.linkAddresses) {
                val addr = la.address
                if (addr is Inet4Address) {
                    localIp = addr.hostAddress
                    break
                }
            }
            for (d in lp.dnsServers) {
                if (d is Inet4Address) {
                    val host = d.hostAddress
                    if (host != null) dns.add(host)
                }
            }
        }

        if (gateway == null || localIp == null) {
            try {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val dhcp = wm.dhcpInfo
                if (dhcp != null) {
                    if (gateway == null && dhcp.gateway != 0) gateway = intToIp(dhcp.gateway)
                    if (localIp == null && dhcp.ipAddress != 0) localIp = intToIp(dhcp.ipAddress)
                }
            } catch (ignored: Exception) {
            }
        }

        out["gateway"] = gateway
        out["localIp"] = localIp
        out["dns"] = dns
        out["bound"] = if (bind) cm.bindProcessToNetwork(net) else false
        return out
    }
}
