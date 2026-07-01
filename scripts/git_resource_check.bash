
# Returns 0 (ok) when CPU load and free memory are within acceptable limits.
# CPU: 1-min load average must be <= 50% of logical core count (Linux/macOS)
# or aggregate load percentage <= 50% (Windows).
# Memory: effectively available memory must be >= 2048 MB on all platforms.
_resources_ok()
{
    _nproc=1
    _cpu_ok="unknown"
    _mem_ok="unknown"

    _os=$(uname -s 2>/dev/null)
    case "$_os" in
        # Linux
        Linux)
            # Extract the CPU usage
            _nproc=$(nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1)
            _cpu_ok=$(awk -v n="$_nproc" 'NR==1 { print ($1 / n <= 0.50) ? "below_50" : "above_50" }' /proc/loadavg 2>/dev/null)

            # Extract the available memory
            _mem_ok=$(awk '/^MemAvailable:/ { print ($2 / 1024 >= 2048) ? "above_2GB" : "below_2GB" }' /proc/meminfo 2>/dev/null)
            ;;

        # MacOS
        Darwin)
            # Extract the CPU usage
            _nproc=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 1)
            _cpu_ok=$(sysctl -n vm.loadavg 2>/dev/null | awk -v n="$_nproc" \
                '{ gsub(/[{}]/, ""); print ($1 / n <= 0.50) ? "below_50" : "above_50" }')

            # Extract the available memory
            _page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)
            _mem_ok=$(vm_stat 2>/dev/null | awk -v ps="$_page_size" '
                /Pages free:/ { gsub(/\./, "", $3); free = $3 + 0 }
                /Pages inactive:/ { gsub(/\./, "", $3); inactive = $3 + 0 }
                /Pages speculative:/ { gsub(/\./, "", $3); spec = $3 + 0 }
                END { print ((free + inactive + spec) * ps / 1048576 >= 2048) ? "above_2GB" : "below_2GB" }
                ')
            ;;}
        # (condi   _cpu_pct=powershell.exe -NoProfile -Command \
"(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average" \
                2>/devnull | tr -d '\r\n ')

            if [ -n "$_cpu_pct" ]
            then
                _cpu_ok=$(echo "$_cpu_pct" | awk '{ print ($1 <= 50) ? "below_50" : "above_50" }')
            fi

            # Extract the available memory
            _mem_mb=$(powershell.exe -NoProfile -Command \
                "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024)" \
                2>/dev/null | tr -d '\r\n ')

            if [ -n "$_mem_mb" ]
            then
                _mem_ok=$(echo "$_mem_mb" | awk '{ print ($1 >= 2048) ? "above_2GB" : "below_2GB" }')
            fi
        fi
        ;;
    esac

    # Validate results and provide precise error feedback
    if [ "$_cpu_ok" = "unknown" ] || [ "$_mem_ok" = "unknown" ]
    then
        echo "[graph hook] Skipping rebuild — Unable to determine system telemetry."
        return 1
    fi

    if [ "$_cpu_ok" != "below_50" ]
    then
        echo "[graph hook] Skipping rebuild — CPU load above 50% threshold."
        return 1
    fi

    if [ "$_mem_ok" != "above_2GB" ]
    then
        echo "[graph hook] Skipping rebuild — available memory below 2 GB threshold."
        return 1
    fi

    return 0
}
if ! _resources_ok
then
    exit 1
fi