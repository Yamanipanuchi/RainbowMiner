﻿using module ..\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

if (-not $IsWindows -and -not $IsLinux) {return}

if ($IsLinux) {
    $Path = ".\Bin\NVIDIA-CcminerMTP\ccminer-linux-cuda"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v1.1.23-ccminermtp/ccminermtp-v1.1.23-linux.7z"
    $Cuda = "9.2"
} else {
    $Path = ".\Bin\NVIDIA-CcminerMTP\ccminer.exe"
    $PathNh = ".\Bin\NVIDIA-CcminerMTP\ccminer-nh.exe"
    $Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v1.1.23-ccminermtp/ccminermtp-v1.1.23-win.7z"
    $Cuda = "10.1"
}
$ManualUri = "https://github.com/zcoinofficial/ccminer/releases"
$Port = "126{0:d2}"
$DevFee = 0.0

if (-not $Session.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "mtp"; MinMemGB = 6; Params = ""} #MTP
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("NVIDIA")
        Name      = $Name
        Path      = $Path
        Port      = $Miner_Port
        Uri       = $Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
    }
    return
}

if (-not (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $Cuda -Warning $Name)) {return}

if ($IsLinux) {
    if (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion "10.1") {
        $Path += "101"
    } elseif (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion "10.0") {
        $Path += "100"
    } else {
        $Path += "92"
    }
}

$Session.DevicesByTypes.NVIDIA | Select-Object Vendor, Model -Unique | ForEach-Object {
    $Device = $Session.DevicesByTypes."$($_.Vendor)" | Where-Object Model -EQ $_.Model
    $Miner_Model = $_.Model

    $Commands | ForEach-Object {
        $Algorithm_Norm = Get-Algorithm $_.MainAlgorithm

        $IsNh = $Pools.$Algorithm_Norm.Name -eq "NiceHash"

        $MinMemGB = $_.MinMemGB
        $Miner_Device = $Device | Where-Object {$_.OpenCL.GlobalMemsize -ge ($MinMemGB * 1gb - 0.25gb)}
        $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
        $Miner_Name = (@("$($Name)$(if ($IsNh) {"Nh"})") + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
        $Miner_Port = Get-MinerPort -MinerName $Name -DeviceName @($Miner_Device.Name) -Port $Miner_Port

        $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ','

		foreach($Algorithm_Norm in @($Algorithm_Norm,"$($Algorithm_Norm)-$($Miner_Model)")) {
			if ($Pools.$Algorithm_Norm.Host -and $Miner_Device -and (-not $IsNh -or ($IsNh -and $PathNh))) {
				$Pool_Port = if ($Pools.$Algorithm_Norm.Ports -ne $null -and $Pools.$Algorithm_Norm.Ports.GPU) {$Pools.$Algorithm_Norm.Ports.GPU} else {$Pools.$Algorithm_Norm.Port}
				[PSCustomObject]@{
					Name           = $Miner_Name
					DeviceName     = $Miner_Device.Name
					DeviceModel    = $Miner_Model
					Path           = "$(if ($IsNh -and $PathNh) {$PathNh} else {$Path})"
					Arguments      = "-R 1 -N 3 -b $($Miner_Port) -d $($DeviceIDsAll) -a $($_.MainAlgorithm) -o $($Pools.$Algorithm_Norm.Protocol)://$($Pools.$Algorithm_Norm.Host):$($Pool_Port) -u $($Pools.$Algorithm_Norm.User)$(if ($Pools.$Algorithm_Norm.Pass) {" -p $($Pools.$Algorithm_Norm.Pass)"})$(if (-not $IsNh -or -not $PathNh) {" --no-donation"}) $($_.Params)"
					HashRates      = [PSCustomObject]@{$Algorithm_Norm = $Session.Stats."$($Miner_Name)_$($Algorithm_Norm -replace '\-.*$')_HashRate".Week}
					API            = "Ccminer"
					Port           = $Miner_Port
					Uri            = $Uri
					DevFee         = 0.0
					FaultTolerance = $_.FaultTolerance
					ExtendInterval = $_.ExtendInterval
					ManualUri      = $ManualUri
                    MiningPriority = 2
				}
			}
		}
    }
}