import Darwin

struct CPUMonitor {
    func currentUsage() -> Double {
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0
        var numCPUsU: natural_t = 0

        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )
        guard err == KERN_SUCCESS, let info = cpuInfo else { return 0 }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        var total = 0.0
        let count = Int(numCPUsU)
        for i in 0..<count {
            let base = Int(CPU_STATE_MAX) * i
            let user   = Double(info[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)])
            let nice   = Double(info[base + Int(CPU_STATE_NICE)])
            let idle   = Double(info[base + Int(CPU_STATE_IDLE)])
            let all    = user + system + nice + idle
            total += all > 0 ? (user + system + nice) / all : 0
        }
        return total / Double(count)
    }
}
