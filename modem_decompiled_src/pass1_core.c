Pass 1: Core functions (using b12 ELF)

======================================================================
[restriction_check] FUN_c0a16da8 @ 0xC0A16DA8 (1936 bytes)
======================================================================

/* WARNING: Possible PIC construction at 0xc0a16f98: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc0a17008: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc0a170fc: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc0a17498: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc0a175ac: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc0a16fa0) */
/* WARNING: Removing unreachable block (ram,0xc0a16fa8) */
/* WARNING: Removing unreachable block (ram,0xc0a16fac) */
/* WARNING: Removing unreachable block (ram,0xc0a17018) */
/* WARNING: Removing unreachable block (ram,0xc0a16fc4) */
/* WARNING: Removing unreachable block (ram,0xc0a16fcc) */
/* WARNING: Removing unreachable block (ram,0xc0a16fd4) */
/* WARNING: Removing unreachable block (ram,0xc0a17020) */
/* WARNING: Removing unreachable block (ram,0xc0a175b0) */
/* WARNING: Restarted to delay deadcode elimination for space: register */

uint FUN_c0a16da8(int param_1)

{
  code **ppcVar1;
  undefined4 uVar2;
  uint uVar3;
  int iVar4;
  uint uVar5;
  int iVar6;
  code *extraout_r1;
  uint extraout_r1_00;
  undefined4 extraout_r1_01;
  int extraout_r1_02;
  code **ppcVar7;
  uint extraout_r1_03;
  code **extraout_r1_04;
  int extraout_r1_05;
  code *extraout_r1_06;
  int iVar8;
  undefined4 *puVar9;
  code *pcVar10;
  code **in_r4;
  code **ppcVar11;
  int unaff_r16;
  int iVar12;
  code **unaff_r17;
  code **unaff_r18;
  int unaff_r19;
  int unaff_r20;
  undefined4 unaff_r21;
  ulonglong in_r23r22;
  ulonglong in_r25r24;
  ulonglong in_r27r26;
  undefined4 *puVar13;
  undefined4 *puVar14;
  undefined4 *puVar15;
  undefined4 uVar16;
  int in_GP;
  sbyte sVar17;
  short sVar18;
  ushort uVar19;
  
  puVar9 = (undefined4 *)&stack0xfffffff8;
  uVar2 = 0xc3454d80;
  iVar6 = *(int *)(param_1 * 4 + -0x3d25a9e0);
  if (iVar6 != 0) {
    iVar6 = *(int *)(iVar6 + 4);
    uVar2 = 0xc3454d8a;
    if (iVar6 != 0) {
      return *(uint *)(iVar6 + 0x7b8);
    }
  }
  uVar16 = 0xc0a16dd8;
  iVar6 = func_0xc10db594(uVar2);
  pcVar10 = extraout_r1;
  puVar15 = puVar9;
SUB_c0a16dd8:
  do {
    puVar13 = puVar9 + -2;
    puVar9[-1] = uVar16;
    *puVar13 = puVar15;
    uVar2 = 0xc3454d4e;
    iVar6 = *(int *)(iVar6 * 4 + -0x3d25a9e0);
    if (iVar6 == 0) {
LAB_c0a16e68:
      func_0xc10db594(uVar2);
    }
    else {
      in_r4 = *(code ***)(iVar6 + 4);
      uVar2 = 0xc3454d58;
      if (in_r4 == (code **)0x0) goto LAB_c0a16e68;
      if (((uint)in_r4[0x1ee] & (uint)pcVar10) == 0) {
        sVar17 = -1;
      }
      else {
        sVar17 = 0;
      }
      if ((((sVar17 != 0) || (pcVar10 == (code *)0x8)) || (pcVar10 == (code *)0x100)) ||
         ((pcVar10 == (code *)0x4000 || (pcVar10 == (code *)0x400000)))) {
        in_r4[0x1ee] = (code *)((uint)in_r4[0x1ee] | (uint)pcVar10);
        if (**(sbyte **)(in_GP + 0x266) != 1) {
          if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
            sVar17 = -1;
          }
          else {
            sVar17 = 0;
          }
          if (sVar17 != 0) {
            return **(uint **)(in_GP + 0x4a30);
          }
          if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
            sVar17 = -1;
          }
          else {
            sVar17 = 0;
          }
          if (sVar17 != 0) {
            return **(uint **)(in_GP + 0x4a34);
          }
        }
        uVar3 = func_0xc0bde33c(0xc1b69078,pcVar10,*(undefined4 *)(*(int *)(iVar6 + 4) + 0x7b8));
        return uVar3;
      }
    }
    uVar2 = 0xc0a16e78;
    iVar4 = func_0xc10db57c(0xc3454d62);
    uVar3 = 0xc3454d26;
    puVar15 = puVar9 + -4;
    puVar9[-3] = uVar2;
    *puVar15 = puVar13;
    puVar9[-6] = unaff_r16;
    puVar9[-5] = unaff_r17;
    iVar12 = *(int *)(iVar4 * 4 + -0x3d25a9e0);
    if (iVar12 != 0) {
      iVar8 = *(int *)(iVar12 + 4);
      uVar3 = 0xc3454d30;
      if (iVar8 == 0) {
        sVar17 = -1;
      }
      else {
        sVar17 = 0;
      }
      if (sVar17 == 0) {
        uVar3 = (uint)*(char *)(iVar8 + 0x8b0);
      }
      if (iVar8 != 0) {
        if (uVar3 == 1) {
          FUN_c0a07700(iVar4,iVar8 + 0x8b4);
          func_0xc0a15690(iVar12);
        }
        uVar3 = 0x19;
        uVar2 = puVar9[-5];
        iVar4 = puVar9[-6];
        uVar16 = puVar9[-3];
        puVar9 = (undefined4 *)*puVar15;
code_r0xc09aae10:
        puVar13[-1] = uVar16;
        puVar13[-2] = puVar9;
        puVar13[-4] = iVar4;
        puVar13[-3] = uVar2;
        uVar2 = func_0xc0714400();
        if (uVar3 < 0x21) {
                    /* WARNING: Could not recover jumptable at 0xc09aae34. Too many branches */
                    /* WARNING: Treating indirect jump as call */
          uVar3 = (**(code **)(**(int **)(in_GP + 0xa5ec) + uVar3 * 4))(uVar2,0xc2da40d9);
          return uVar3;
        }
        if (**(sbyte **)(in_GP + 0x266) != 1) {
          if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
            sVar17 = -1;
          }
          else {
            sVar17 = 0;
          }
          if (sVar17 != 0) {
            return **(uint **)(in_GP + 0x4a30);
          }
          if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
            sVar17 = -1;
          }
          else {
            sVar17 = 0;
          }
          if (sVar17 != 0) {
            return **(uint **)(in_GP + 0x4a34);
          }
        }
        uVar3 = func_0xc0bde2c8();
        return uVar3;
      }
    }
    uVar2 = 0xc0a16ecc;
    iVar4 = func_0xc10db594(uVar3);
    puVar13 = puVar9 + -8;
    puVar9[-7] = uVar2;
    *puVar13 = puVar15;
    uVar2 = 0xc3454d3a;
    iVar4 = *(int *)(iVar4 * 4 + -0x3d25a9e0);
    if (iVar4 != 0) {
      iVar4 = *(int *)(iVar4 + 4);
      uVar2 = 0xc3454d44;
      if (iVar4 != 0) {
        return (uint)*(char *)(iVar4 + 0x8b0);
      }
    }
    uVar16 = 0xc0a16f00;
    uVar5 = func_0xc10db594(uVar2);
    uVar3 = extraout_r1_00;
    puVar14 = puVar13;
    while( true ) {
      puVar14[-1] = uVar16;
      puVar14[-2] = puVar13;
      uVar2 = 0xc3454d6c;
      iVar4 = *(int *)(uVar5 * 4 + -0x3d25a9e0);
      if (iVar4 != 0) {
        iVar6 = *(int *)(iVar4 + 4);
        uVar2 = 0xc3454d76;
        if (iVar6 == 0) {
          sVar17 = -1;
        }
        else {
          sVar17 = 0;
        }
        if (sVar17 == 0) {
          in_r4 = (code **)0xffffffff;
        }
        if (iVar6 != 0) {
          *(uint *)(iVar6 + 0x7b8) = *(uint *)(iVar6 + 0x7b8) & (uVar3 ^ (uint)in_r4);
          if (**(sbyte **)(in_GP + 0x266) != 1) {
            if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
              sVar17 = -1;
            }
            else {
              sVar17 = 0;
            }
            if (sVar17 != 0) {
              return **(uint **)(in_GP + 0x4a30);
            }
            if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
              sVar17 = -1;
            }
            else {
              sVar17 = 0;
            }
            if (sVar17 != 0) {
              return **(uint **)(in_GP + 0x4a34);
            }
          }
          uVar3 = func_0xc0bde33c(0xc1b69080,uVar3,*(undefined4 *)(*(int *)(iVar4 + 4) + 0x7b8));
          return uVar3;
        }
        iVar6 = 0;
      }
      uVar16 = 0xc0a16f6c;
      iVar4 = func_0xc10db594(uVar2);
      puVar9 = puVar14 + -4;
      puVar14[-3] = uVar16;
      *puVar9 = puVar14 + -2;
      puVar13 = puVar14 + -8;
      puVar14[-6] = iVar12;
      puVar14[-5] = unaff_r17;
      puVar14[-8] = unaff_r18;
      puVar14[-7] = unaff_r19;
      unaff_r18 = (code **)0xc3454d94;
      unaff_r19 = *(int *)(iVar4 * 4 + -0x3d25a9e0);
      if ((unaff_r19 != 0) && (unaff_r18 = (code **)0xc3454d9e, *(int *)(unaff_r19 + 4) != 0)) {
        uVar3 = 0x1c;
        uVar16 = 0xc0a16fa0;
        uVar2 = extraout_r1_01;
        goto code_r0xc09aae10;
      }
      uVar2 = 0xc0a17040;
      iVar12 = unaff_r19;
      uVar5 = func_0xc10db594(unaff_r18);
      puVar13 = puVar14 + -10;
      puVar14[-9] = uVar2;
      *puVar13 = puVar9;
      puVar14[-0xc] = iVar4;


  [... truncated, 20762 chars total ...]

======================================================================
[open_logical_channel] FUN_c0a15234 @ 0xC0A15234 (432 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: register */
/* WARNING: Restarted to delay deadcode elimination for space: stack */

uint FUN_c0a15234(ushort param_1,int param_2,uint param_3)

{
  char cVar1;
  int iVar2;
  int iVar3;
  int iVar4;
  undefined4 uVar5;
  uint uVar6;
  uint uVar7;
  int in_GP;
  sbyte sVar8;
  undefined1 auStack_80 [16];
  undefined1 uStack_70;
  undefined2 uStack_6e;
  undefined1 *puStack_60;
  undefined4 uStack_5c;
  uint uStack_58;
  undefined4 uStack_54;
  uint uStack_50;
  uint uStack_4c;
  undefined4 uStack_48;
  undefined1 auStack_40 [16];
  undefined1 uStack_30;
  ushort uStack_2e;
  undefined1 uStack_2c;
  undefined2 uStack_2a;
  undefined2 uStack_28;
  char cStack_26;
  
  iVar2 = func_0xc0714400();
  cStack_26 = *(char *)(param_2 + 7);
  uVar6 = (uint)cStack_26;
  if (uVar6 == 0) {
    return 1;
  }
  if (uVar6 == 9) {
    sVar8 = -1;
  }
  else {
    sVar8 = 0;
  }
  if (sVar8 == 0) {
    param_3 = uVar6 - 6;
  }
  if (uVar6 == 9) {
    return 1;
  }
  if ((param_3 & 0xff) < 2) {
    sVar8 = 0;
  }
  else {
    sVar8 = -1;
  }
  uStack_28 = *(undefined2 *)(param_2 + 4);
  uStack_2a = *(undefined2 *)(param_2 + 2);
  uStack_30 = 2;
  uStack_2e = param_1;
  if (sVar8 == 0) {
LAB_c0a15290:
    uVar6 = 1;
    uStack_2c = 1;
  }
  else {
    iVar3 = thunk_EXT_FUN_c0717d4c(iVar2,param_1);
    if (iVar3 == 1) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    iVar4 = iVar3;
    if (sVar8 == 0) {
      iVar4 = iVar2;
    }
    if (iVar3 == 1) goto LAB_c0a15290;
    uVar6 = FUN_c0a16da8(iVar4);
    if ((uVar6 & 4) == 0) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 == 0) {
      uVar6 = 1;
      if (*(sbyte *)(param_2 + 7) != 8) {
        uVar6 = 3;
      }
    }
    else {
      if (uStack_2e == 0x3c) {
        uVar6 = FUN_c0a16da8(iVar2);
        if ((uVar6 & 0x100) == 0) {
          sVar8 = -1;
        }
        else {
          sVar8 = 0;
        }
        uVar6 = 1;
        if ((sVar8 == 0) &&
           ((iVar3 = FUN_c0999610(), iVar3 != 0 || (iVar3 = FUN_c0999630(), iVar3 != 0))))
        goto LAB_c0a15304;
      }
      iVar3 = thunk_EXT_FUN_c0717d4c(iVar2,uStack_2e);
      if (iVar3 == 1) {
        sVar8 = -1;
      }
      else {
        sVar8 = 0;
      }
      uVar6 = 1;
      if (sVar8 == 0) {
        uStack_2c = 2;
        uVar6 = 3;
      }
    }
  }
LAB_c0a15304:
  uVar7 = (uint)uStack_2e;
  uVar5 = thunk_EXT_FUN_c0717d4c();
  if (**(sbyte **)(in_GP + 0x266) != 1) {
    if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 != 0) goto LAB_c0a1535c;
    if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 != 0) goto LAB_c0a1535c;
  }
  cVar1 = *(char *)(param_2 + 7);
  uStack_48 = FUN_c0a16da8(iVar2);
  uStack_58 = uVar7;
  uStack_54 = uVar5;
  uStack_50 = uVar6;
  uStack_4c = (uint)cVar1;
  func_0xc0bde450();
LAB_c0a1535c:
  func_0xc0715c10(auStack_40,0x402,0x4020200);
  iVar2 = func_0xc0716820(auStack_40,0x20);
  if (iVar2 == 0) {
    return uVar6;
  }
  uVar5 = 0xc0a15390;
  uStack_6e = func_0xc10db594(0xc3454bb4);
  uStack_70 = 4;
  puStack_60 = &stack0xfffffff8;
  uStack_5c = uVar5;
  func_0xc0715c10(auStack_80,0x402);
  iVar2 = func_0xc0716820(auStack_80,0x20);
  if (iVar2 == 0) {
    return 0;
  }
  func_0xc10db594(0xc3454bbe);
  iVar2 = func_0xc0717134(0xc2149db0);
  return (uint)(iVar2 != -2);
}



======================================================================
[aid_check] FUN_c0985cc4 @ 0xC0985CC4 (120 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: register */

undefined4 FUN_c0985cc4(undefined4 param_1,int param_2)

{
  int iVar1;
  int iVar2;
  int in_GP;
  sbyte sVar3;
  
  iVar1 = func_0xc0717168();
  if ((iVar1 == param_2) || (iVar2 = FUN_c09847f8(), iVar2 != 0)) {
    FUN_c098acc0();
    return 1;
  }
  if (**(sbyte **)(in_GP + 0x266) != 1) {
    if ((**(uint **)(in_GP + 0x4a30) & 0x2008) == 0) {
      sVar3 = -1;
    }
    else {
      sVar3 = 0;
    }
    if (sVar3 != 0) {
      return 0;
    }
    if ((**(uint **)(in_GP + 0x4a34) & 0x2008) == 0) {
      sVar3 = -1;
    }
    else {
      sVar3 = 0;
    }
    if (sVar3 != 0) {
      return 0;
    }
  }
  func_0xc0bde33c(0xc1b64848,iVar1,param_2);
  return 0;
}



======================================================================
[lpa_isdr_filter_1] FUN_c0f115e8 @ 0xC0F115E8 (100 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void FUN_c0f115e8(void)

{
  short sVar1;
  int iVar2;
  undefined4 unaff_r16;
  undefined4 *unaff_r17;
  undefined4 unaff_r20;
  undefined4 in_stack_00000000;
  undefined4 in_stack_00000004;
  
  sVar1 = FUN_c14b4540();
  func_0xc0f11734(unaff_r20);
  if ((sVar1 == 0) && (sVar1 = FUN_c14b408c(unaff_r16,&stack0x00000000), sVar1 == 0)) {
    iVar2 = func_0xc0f11728(in_stack_00000004);
    unaff_r17[1] = iVar2;
    if (iVar2 != 0) {
      *unaff_r17 = in_stack_00000004;
      func_0xc0714250(iVar2,in_stack_00000004,in_stack_00000000,in_stack_00000004);
    }
  }
  func_0xc14b4004(unaff_r16);
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_isdr_filter_2] FUN_c0f116b4 @ 0xC0F116B4 (108 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void FUN_c0f116b4(undefined4 param_1)

{
  short sVar1;
  int iVar2;
  undefined4 unaff_r16;
  undefined4 *unaff_r17;
  undefined4 unaff_r18;
  int unaff_r21;
  undefined4 in_stack_00000000;
  undefined4 in_stack_00000004;
  
  *(undefined4 *)(unaff_r21 + 8) = param_1;
  sVar1 = FUN_c14b4540(unaff_r18,0xc1cd064e,&stack0x00000008);
  func_0xc0f11734();
  if ((sVar1 == 0) && (sVar1 = FUN_c14b408c(unaff_r16,&stack0x00000000), sVar1 == 0)) {
    iVar2 = func_0xc0f11728(in_stack_00000004);
    unaff_r17[1] = iVar2;
    if (iVar2 != 0) {
      *unaff_r17 = in_stack_00000004;
      func_0xc0714250(iVar2,in_stack_00000004,in_stack_00000000,in_stack_00000004);
    }
  }
  func_0xc14b4004(unaff_r16);
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_isdr_filter_3] FUN_c0f11758 @ 0xC0F11758 (596 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */
/* WARNING: Possible PIC construction at 0xc0f11808: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc0f11810) */
/* WARNING: Removing unreachable block (ram,0xc0f1181c) */
/* WARNING: Removing unreachable block (ram,0xc0f11850) */
/* WARNING: Removing unreachable block (ram,0xc0f11854) */
/* WARNING: Restarted to delay deadcode elimination for space: register */
/* WARNING: Restarted to delay deadcode elimination for space: stack */

void FUN_c0f11758(undefined4 param_1)

{
  uint uVar1;
  undefined1 uVar2;
  sbyte sVar3;
  undefined1 *puVar4;
  sbyte *psVar5;
  undefined1 *puVar6;
  undefined4 uVar7;
  int iVar8;
  undefined8 in_r3r2;
  undefined1 *in_r5;
  undefined4 unaff_r16;
  code *unaff_r17;
  uint uVar9;
  uint unaff_r18;
  undefined4 unaff_r20;
  undefined4 unaff_r21;
  int *piVar10;
  int in_GP;
  sbyte sVar11;
  uint in_stack_00000000;
  undefined1 in_stack_00000004;
  undefined1 *in_stack_00000008;
  uint in_stack_0000000c;
  undefined4 in_stack_0000001c;
  undefined4 in_stack_00000020;
  undefined4 in_stack_00000068;
  undefined4 in_stack_0000006c;
  undefined4 uStack00000078;
  int iStack0000007c;
  
  iStack0000007c = (int)((ulonglong)in_r3r2 >> 0x20);
  *in_r5 = 10;
  uStack00000078 = 0x7fffffff;
  thunk_EXT_FUN_c070df10(param_1,0xc1cd0678);
  thunk_EXT_FUN_c070e4e0(&stack0x00000040,0);
  in_stack_00000068 = unaff_r20;
  if (unaff_r18 < 2) {
    if (*(longlong *)(unaff_r18 * 8 + -0x3d811d98) == CONCAT44(unaff_r21,unaff_r20)) {
      sVar11 = -1;
    }
    else {
      sVar11 = 0;
    }
    if (sVar11 == 0) {
      func_0xc0bde2c8();
      (*unaff_r17)(0,0,unaff_r16);
    }
    else {
      *(sbyte *)((uint)&stack0x00000040 | 3) = (sbyte)unaff_r18;
      puVar4 = (undefined1 *)FUN_c0f12d14(unaff_r18,&stack0x00000078);
      if (puVar4 == (undefined1 *)0x0) {
        sVar11 = -1;
      }
      else {
        sVar11 = 0;
      }
      puVar6 = puVar4;
      if (sVar11 != 0) {
        puVar6 = (undefined1 *)register0x00000074;
      }
      if (puVar4 == (undefined1 *)0x0) {
        *(uint *)((uint)&stack0x00000068 | 4) = (uint)&stack0x00000028 | 1;
        in_stack_00000068 = 0x10;
        thunk_EXT_FUN_c070df10(puVar6,&stack0x00000040);
        puVar4 = &stack0x0000003f;
        goto SUB_c0f11890;
      }
    }
  }
  if (**(int **)(in_GP + 20000) == iStack0000007c) {
                    /* WARNING: Bad instruction - Truncating control flow here */
    halt_baddata();
  }
  puVar4 = (undefined1 *)func_0xc08f9b60();
SUB_c0f11890:
  psVar5 = (sbyte *)thunk_EXT_FUN_c070dd00(puVar4);
  uVar1 = in_stack_00000000;
  if (psVar5 != (sbyte *)0x0) {
    uVar2 = in_stack_00000000._1_1_;
    func_0xc0bde33c(0xc1a626c8,in_stack_00000000 & 0xff,in_stack_00000000 >> 8 & 0xff);
    sVar11 = 0;
    do {
      sVar3 = sVar11;
      if ((char)sVar3 < '\n') {
        sVar11 = 0;
      }
      else {
        sVar11 = -1;
      }
      uVar9 = (uint)(char)sVar3;
    } while ((sVar11 == 0) && (sVar11 = sVar3 + 1, *(int *)(uVar9 * 4 + -0x3d811d70) != 0));
    if (sVar3 == 10) {
      sVar11 = -1;
    }
    else {
      sVar11 = 0;
    }
    if (sVar11 == 0) {
      puVar6 = (undefined1 *)func_0xc0f12bb0(0x24);
      puVar4 = in_stack_00000008;
      *(undefined1 **)(uVar9 * 4 + -0x3d811d70) = puVar6;
      if (puVar6 != (undefined1 *)0x0) {
        piVar10 = (int *)(uVar9 * 4 + -0x3d811d70);
        if (in_stack_00000008 == (undefined1 *)0x0) {
          sVar11 = -1;
        }
        else {
          sVar11 = 0;
        }
        if (sVar11 == 0) {
          uVar9 = in_stack_0000000c;
        }
        if (in_stack_00000008 != (undefined1 *)0x0) {
          if (uVar9 == 0) {
            sVar11 = -1;
          }
          else {
            sVar11 = 0;
          }
          if (sVar11 == 0) {
            puVar6 = in_stack_00000008;
          }
          if (uVar9 != 0) {
            uVar7 = func_0xc0f12ba4();
            *(undefined4 *)(*piVar10 + 0xc) = uVar7;
            iVar8 = *(int *)(*piVar10 + 0xc);
            if (iVar8 == 0) {
              sVar11 = -1;
            }
            else {
              sVar11 = 0;
            }
            if (sVar11 == 0) {
              *(undefined1 **)(*piVar10 + 8) = puVar4;
            }
            if (iVar8 == 0) {
              halt_baddata();
            }
            func_0xc0714250(*(undefined4 *)(*piVar10 + 0xc),*(undefined4 *)(*piVar10 + 8));
            puVar6 = (undefined1 *)*piVar10;
          }
        }
        *puVar6 = (sbyte)uVar1;
        *(undefined1 *)(*piVar10 + 3) = 0;
        *(undefined1 *)(*piVar10 + 1) = uVar2;
        *(undefined1 *)(*piVar10 + 2) = 0;
        *(undefined1 *)(*piVar10 + 4) = in_stack_00000004;
        thunk_EXT_FUN_c070df10(*piVar10 + 0x10,&stack0x00000010);
        *(undefined4 *)(*piVar10 + 0x1c) = in_stack_0000001c;
        iVar8 = *piVar10;
        *psVar5 = sVar3;
        *(undefined4 *)(iVar8 + 0x20) = in_stack_00000020;
      }
    }
    else {
      func_0xc0bde25c(0xc1a626d0);
    }
  }
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[nv_init_dispatch] FUN_c1611600 @ 0xC1611600 (88 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */
/* WARNING: Restarted to delay deadcode elimination for space: register */

void FUN_c1611600(undefined4 param_1,int param_2)

{
  uint uVar1;
  uint extraout_r1;
  uint uVar2;
  undefined4 *unaff_r17;
  int in_GP;
  sbyte sVar3;
  int in_stack_00000134;
  
  *unaff_r17 = *(undefined4 *)(param_2 + 0xc);
  if (**(int **)(in_GP + 20000) != in_stack_00000134) {
    func_0xc1801040();
    uVar1 = func_0xc0f10630();
    if (uVar1 != 0) {
      uVar2 = extraout_r1 >> 8;
      if (uVar2 < 10) {
        sVar3 = 0;
      }
      else {
        sVar3 = -1;
      }
      if (sVar3 == 0) {
        uVar1 = extraout_r1 & 0xff;
      }
      if (uVar2 < 10) {
                    /* WARNING: Could not recover jumptable at 0xc161164c. Too many branches */
                    /* WARNING: Treating indirect jump as call */
        (**(code **)(**(int **)(in_GP + 0xbbe4) + uVar2 * 4))(uVar1);
        return;
      }
    }
  }
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}




Done.
