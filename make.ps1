[CmdletBinding()]
Param(
    [Parameter(Position=1)]
    [String] $Target = "build",
    [String] $AdditionalArgs = '',
    [String] $Build = '',
    [String] $RemotingVersion = '4.3',
    [String] $BuildNumber = "1",
    [int] $WindowsTag = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
)

$Repository = 'agent'
$Organization = 'jenkins'

if(![String]::IsNullOrWhiteSpace($env:DOCKERHUB_REPO)) {
    $Repository = $env:DOCKERHUB_REPO
}

if(![String]::IsNullOrWhiteSpace($env:DOCKERHUB_ORGANISATION)) {
    $Organization = $env:DOCKERHUB_ORGANISATION
}

$builds = @{
    'jdk8' = @{'Dockerfile' = 'Dockerfile-windows' ; 'Tags' = @( "latest", "windowsservercore-$WindowsTag", "jdk8", "windowsservercore-$WindowsTag-jdk8" ) };
    'jdk11' = @{'DockerFile' = 'Dockerfile-windows-jdk11'; 'Tags' = @( "windowsservercore-$WindowsTag-jdk11", "jdk11" ) };
    'nanoserver' = @{'DockerFile' = 'Dockerfile-windows-nanoserver'; 'Tags' = @( "nanoserver-$WindowsTag", "nanoserver-$WindowsTag-jdk8" ) };
    'nanoserver-jdk11' = @{'DockerFile' = 'Dockerfile-windows-nanoserver-jdk11'; 'Tags' = @( "nanoserver-$WindowsTag-jdk11" ) };
}

if(![System.String]::IsNullOrWhiteSpace($Build) -and $builds.ContainsKey($Build)) {
    foreach($tag in $builds[$Build]['Tags']) {
        Write-Host "Building $Build => tag=$tag"
        $cmd = "docker build -f {0} --build-arg WINDOWS_DOCKER_TAG=$WindowsTag --build-arg VERSION='$RemotingVersion' -t {1}/{2}:{3} {4} ." -f $builds[$Build]['Dockerfile'], $Organization, $Repository, $tag, $AdditionalArgs
        Invoke-Expression $cmd

        $buildTag = "$RemotingVersion-$BuildNumber-$tag"
        if($tag -eq 'latest') {
            $buildTag = "$RemotingVersion-$BuildNumber"
        }
        Write-Host "Building $Build => tag=$buildTag"
        $cmd = "docker build -f {0} --build-arg WINDOWS_DOCKER_TAG=$WindowsTag --build-arg VERSION='$RemotingVersion' -t {1}/{2}:{3} {4} ." -f $builds[$Build]['Dockerfile'], $Organization, $Repository, $buildTag, $AdditionalArgs
        Invoke-Expression $cmd
    }
} else {
    foreach($b in $builds.Keys) {
        foreach($tag in $builds[$b]['Tags']) {
            Write-Host "Building $b => tag=$tag"
            $cmd = "docker build -f {0} --build-arg WINDOWS_DOCKER_TAG=$WindowsTag --build-arg VERSION='$RemotingVersion' -t {1}/{2}:{3} {4} ." -f $builds[$b]['Dockerfile'], $Organization, $Repository, $tag, $AdditionalArgs
            Invoke-Expression $cmd

            $buildTag = "$RemotingVersion-$BuildNumber-$tag"
            if($tag -eq 'latest') {
                $buildTag = "$RemotingVersion-$BuildNumber"
            }
            Write-Host "Building $Build => tag=$buildTag"
            $cmd = "docker build -f {0} --build-arg WINDOWS_DOCKER_TAG=$WindowsTag --build-arg VERSION='$RemotingVersion' -t {1}/{2}:{3} {4} ." -f $builds[$b]['Dockerfile'], $Organization, $Repository, $buildTag, $AdditionalArgs
            Invoke-Expression $cmd
        }
    }
}

if($lastExitCode -ne 0) {
    exit $lastExitCode
}

if($target -eq "test") {
    $mod = Get-InstalledModule -Name Pester -RequiredVersion 4.9.0 -ErrorAction SilentlyContinue
    if($null -eq $mod) {
        $module = "c:\Program Files\WindowsPowerShell\Modules\Pester"
        takeown /F $module /A /R
        icacls $module /reset
        icacls $module /grant Administrators:'F' /inheritance:d /T
        Remove-Item -Path $module -Recurse -Force -Confirm:$false
        Install-Module -Force -Name Pester -RequiredVersion 4.9.0
    }

    if(![System.String]::IsNullOrWhiteSpace($Build) -and $builds.ContainsKey($Build)) {
        $env:FLAVOR = $Build
        Invoke-Pester -Path tests -EnableExit
        Remove-Item env:\FLAVOR
    } else {
        foreach($b in $builds.Keys) {
            $env:FLAVOR = $b
            Invoke-Pester -Path tests -EnableExit
            Remove-Item env:\FLAVOR
        }
    }
}

if($target -eq "publish") {
    if(![System.String]::IsNullOrWhiteSpace($Build) -and $builds.ContainsKey($Build)) {
        foreach($tag in $Builds[$Build]['Tags']) {
            Write-Host "Publishing $Build => tag=$tag"
            $cmd = "docker push {0}/{1}:{2}" -f $Organization, $Repository, $tag
            Invoke-Expression $cmd

            $buildTag = "$RemotingVersion-$BuildNumber-$tag"
            if($tag -eq 'latest') {
                $buildTag = "$RemotingVersion-$BuildNumber"
            }
            Write-Host "Publishing $Build => tag=$buildTag"
            $cmd = "docker push {0}/{1}:{2}" -f $Organization, $Repository, $buildTag
            Invoke-Expression $cmd
        }
    } else {
        foreach($b in $builds.Keys) {
            foreach($tag in $Builds[$b]['Tags']) {
                Write-Host "Publishing $b => tag=$tag"
                $cmd = "docker push {0}/{1}:{2}" -f $Organization, $Repository, $tag
                Invoke-Expression $cmd

                $buildTag = "$RemotingVersion-$BuildNumber-$tag"
                if($tag -eq 'latest') {
                    $buildTag = "$RemotingVersion-$BuildNumber"
                }
                Write-Host "Publishing $Build => tag=$buildTag"
                $cmd = "docker push {0}/{1}:{2}" -f $Organization, $Repository, $buildTag
                Invoke-Expression $cmd
            }
        }
    }
}


if($lastExitCode -ne 0) {
    Write-Error "Build failed!"
} else {
    Write-Host "Build finished successfully"
}
exit $lastExitCode
