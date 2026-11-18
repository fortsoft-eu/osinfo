object MainForm: TMainForm
  Left = 192
  Top = 107
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'OS Info'
  ClientHeight = 285
  ClientWidth = 455
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  KeyPreview = True
  OldCreateOrder = False
  Position = poDefaultPosOnly
  OnCreate = FormCreate
  OnKeyDown = FormKeyDown
  DesignSize = (
    455
    285)
  PixelsPerInch = 96
  TextHeight = 13
  object OperatingSystemLabel: TLabel
    Left = 8
    Top = 3
    Width = 439
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'Operating system version'
  end
  object VirtualBoxNameLabel: TLabel
    Left = 8
    Top = 44
    Width = 439
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'VirtualBox friendly name'
  end
  object ProcessorLabel: TLabel
    Left = 8
    Top = 85
    Width = 439
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'Processor model'
  end
  object ArchitectureLabel: TLabel
    Left = 8
    Top = 126
    Width = 215
    Height = 15
    AutoSize = False
    Caption = 'Processor architecture'
  end
  object ProcessorCountLabel: TLabel
    Left = 231
    Top = 126
    Width = 216
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'Processors'
  end
  object MemoryLabel: TLabel
    Left = 8
    Top = 167
    Width = 215
    Height = 15
    AutoSize = False
    Caption = 'Total RAM'
  end
  object SystemDiskLabel: TLabel
    Left = 231
    Top = 167
    Width = 216
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'Total system disk size'
  end
  object DotNetLabel: TLabel
    Left = 8
    Top = 208
    Width = 439
    Height = 15
    Anchors = [akLeft, akTop, akRight]
    AutoSize = False
    Caption = 'Available .NET runtimes'
  end
  object OperatingSystemEdit: TEdit
    Left = 8
    Top = 19
    Width = 439
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 0
  end
  object VirtualBoxNameEdit: TEdit
    Left = 8
    Top = 60
    Width = 439
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 1
  end
  object ProcessorEdit: TEdit
    Left = 8
    Top = 101
    Width = 439
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 2
  end
  object ArchitectureEdit: TEdit
    Left = 8
    Top = 142
    Width = 215
    Height = 21
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 3
  end
  object ProcessorCountEdit: TEdit
    Left = 231
    Top = 142
    Width = 216
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 4
  end
  object MemoryEdit: TEdit
    Left = 8
    Top = 183
    Width = 215
    Height = 21
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 5
  end
  object SystemDiskEdit: TEdit
    Left = 231
    Top = 183
    Width = 216
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 6
  end
  object DotNetEdit: TEdit
    Left = 8
    Top = 224
    Width = 439
    Height = 21
    Anchors = [akLeft, akTop, akRight]
    Color = clBtnFace
    ReadOnly = True
    TabOrder = 7
  end
  object RefreshButton: TButton
    Left = 8
    Top = 252
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = '&Refresh'
    TabOrder = 8
    OnClick = RefreshButtonClick
  end
  object CopyButton: TButton
    Left = 91
    Top = 252
    Width = 75
    Height = 25
    Anchors = [akLeft, akBottom]
    Caption = '&Copy'
    TabOrder = 9
    OnClick = CopyButtonClick
  end
  object CloseButton: TButton
    Left = 372
    Top = 252
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Cancel = True
    Caption = 'Close'
    Default = True
    TabOrder = 10
    OnClick = CloseButtonClick
  end
end
