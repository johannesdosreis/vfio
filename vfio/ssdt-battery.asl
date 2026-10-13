/*
 * Fake battery for the Windows VM. The NVIDIA driver for laptop GPUs looks for a
 * battery and fails with Code 43 when the system has none.
 * Compiled with: iasl ssdt-battery.asl  -> ssdt-battery.aml (passed to QEMU with -acpitable)
 */
DefinitionBlock ("", "SSDT", 1, "BOCHS", "BXPCSSDT", 0x00000001)
{
    Scope (\_SB)
    {
        Device (BAT0)
        {
            Name (_HID, EisaId ("PNP0C0A"))
            Name (_UID, One)

            Method (_STA, 0, NotSerialized)
            {
                Return (0x0F)
            }

            Method (_BIF, 0, NotSerialized)
            {
                Return (Package (0x0D)
                {
                    One,        // power unit: mA / mAh
                    0x1770,     // design capacity: 6000 mAh
                    0x1770,     // last full charge capacity: 6000 mAh
                    One,        // rechargeable
                    0x39D0,     // design voltage: 14800 mV
                    0x0258,     // warning capacity
                    0x012C,     // low capacity
                    0x3C,       // granularity 1
                    0x3C,       // granularity 2
                    "",         // model
                    "",         // serial
                    "LION",     // type
                    ""          // OEM
                })
            }

            Method (_BST, 0, NotSerialized)
            {
                Return (Package (0x04)
                {
                    Zero,       // state: neither charging nor discharging
                    Zero,       // present rate
                    0x1770,     // remaining capacity: full
                    0x39D0      // present voltage
                })
            }
        }
    }
}
