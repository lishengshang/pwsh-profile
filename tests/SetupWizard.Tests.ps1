Describe '安装向导选择' {
    BeforeAll {
        . (Join-Path (Split-Path $PSScriptRoot -Parent) 'Scripts/Invoke-SetupWizard.ps1')
        $tools = @(
            @{ Name = 'starship'; Id = 'Starship.Starship'; Component = 'core'; Desc = '提示符' }
            @{ Name = 'lazygit'; Id = 'JesseDuffield.lazygit'; Component = 'gitui'; Desc = 'Git 界面' }
        )
    }

    BeforeEach {
        $script:wizardAnswers = [Collections.Generic.Queue[string]]::new()
        Mock -CommandName Read-Host -MockWith {
            if (!$script:wizardAnswers.Count) { throw '向导请求了意外输入' }
            $script:wizardAnswers.Dequeue()
        }
        Mock -CommandName Write-Host -MockWith {}
    }

    It '<Name>' -ForEach @(
        @{ Name = '取消默认组件'; Answers = @('gitui', '', ''); Components = 'core,completion'; Excluded = '' }
        @{ Name = '首次剔除工具'; Answers = @('', '1', ''); Components = 'core,completion,gitui'; Excluded = 'starship' }
        @{ Name = '恢复工具后再次剔除'; Answers = @('', '1', '1', '1', ''); Components = 'core,completion,gitui'; Excluded = 'starship' }
        @{ Name = '清空组件后确认'; Answers = @('core,completion,gitui', '', ''); Components = ''; Excluded = '' }
        @{ Name = '清空组件后重新选中'; Answers = @('core,completion,gitui', 'core', '', ''); Components = 'core'; Excluded = '' }
        @{ Name = '返回后移除对应组件'; Answers = @('', '2', 'b', 'gitui', '', ''); Components = 'core,completion'; Excluded = '' }
    ) {
        $ErrorActionPreference = 'Stop'
        foreach ($answer in $Answers) { $script:wizardAnswers.Enqueue($answer) }

        $selection = Invoke-SetupWizard -Tools $tools -DefaultComponents @('core', 'completion', 'gitui') -ComponentModules @{}

        $selection | Should -BeOfType [hashtable]
        ($selection.Components -join ',') | Should -BeExactly $Components
        ($selection.ExcludeTools -join ',') | Should -BeExactly $Excluded
        $script:wizardAnswers.Count | Should -Be 0
    }

    It '可在<Name>退出' -ForEach @(
        @{ Name = '组件页'; Answers = @('q') }
        @{ Name = '工具预览页'; Answers = @('', 'q') }
    ) {
        $ErrorActionPreference = 'Stop'
        foreach ($answer in $Answers) { $script:wizardAnswers.Enqueue($answer) }

        $selection = Invoke-SetupWizard -Tools $tools -DefaultComponents @('core', 'completion', 'gitui') -ComponentModules @{}

        $selection | Should -BeNullOrEmpty
        $script:wizardAnswers.Count | Should -Be 0
    }
}
