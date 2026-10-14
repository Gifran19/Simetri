import 'package:flutter/material.dart';

class DeviceStatusCard extends StatelessWidget {
  final bool connected;
  final bool power;
  final ValueChanged<bool> onChanged;

  const DeviceStatusCard({
    super.key,
    required this.connected,
    required this.power,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xff10233F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // STATUS DEVICE
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: connected
                          ? const Color(0xff00D9A6)
                          : Colors.redAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (connected
                                  ? const Color(0xff00D9A6)
                                  : Colors.redAccent)
                              .withValues(alpha: 0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connected ? 'Perangkat Terhubung' : 'Perangkat Offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Icon(
                connected ? Icons.wifi : Icons.wifi_off,
                color: connected ? const Color(0xff00D9A6) : Colors.grey,
                size: 20,
              ),
            ],
          ),

          const SizedBox(height: 14),

          // CONNECTION + SWITCH
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xff071426),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: connected
                          ? const Color(0xff00D9A6).withValues(alpha: 0.3)
                          : Colors.white24,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        connected ? Icons.wifi : Icons.bluetooth_disabled,
                        size: 14,
                        color: connected
                            ? const Color(0xff00D9A6)
                            : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          connected ? 'Smart Meter WiFi' : 'Belum terhubung',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: connected ? Colors.white : Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    power ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: power ? const Color(0xff00D9A6) : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: power,
                    activeThumbColor: const Color(0xff00D9A6),
                    activeTrackColor:
                        const Color(0xff00D9A6).withValues(alpha: 0.4),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white12,
                    onChanged: connected ? onChanged : null,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}