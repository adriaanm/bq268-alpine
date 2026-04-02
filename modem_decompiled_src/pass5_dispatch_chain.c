Pass 5: MMGSDI dispatch chain (b12 + full ELF)

======================================================================
[dispatch_table_store] FUN_c1736674 @ 0xC1736674 (400 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: stack */

int FUN_c1736674(int param_1,undefined4 param_2)

{
  int *piVar1;
  sbyte *psVar2;
  int iVar3;
  int extraout_r1;
  int *piVar4;
  uint uVar5;
  int in_GP;
  sbyte sVar6;
  sbyte sVar7;
  sbyte sVar8;
  int aiStack_40 [2];
  undefined4 uStack_38;
  undefined4 uStack_34;
  undefined1 *puStack_30;
  undefined1 auStack_28 [12];
  int iStack_1c;
  
  if (param_1 == 0) {
    sVar6 = -1;
  }
  else {
    sVar6 = 0;
  }
  if (sVar6 == 0) {
    *(undefined4 *)(param_1 + 0x14) = param_2;
    return param_1;
  }
  psVar2 = (sbyte *)func_0xc10db594(0xc3478b10);
  if (extraout_r1 == 0) {
    sVar6 = -1;
  }
  else {
    sVar6 = 0;
  }
  iStack_1c = **(int **)(in_GP + 20000);
  if ((sVar6 != 0) || (psVar2 == (sbyte *)0x0)) {
    while( true ) {
      iVar3 = 1;
      func_0xc13e477c(0xc1bf43a4);
LAB_c17367c0:
      if (**(int **)(in_GP + 20000) == iStack_1c) break;
      func_0xc1801040();
    }
    return iVar3;
  }
  piVar4 = (int *)0xc1f8b648;
  do {
    if (*piVar4 == 0) break;
    piVar1 = piVar4 + 1;
    if ((sbyte)*piVar1 == *psVar2) {
      sVar6 = -1;
    }
    else {
      sVar6 = 0;
    }
    if (sVar6 != 0) {
      aiStack_40[0] = *piVar4;
    }
    piVar4 = piVar4 + 2;
  } while ((sbyte)*piVar1 != *psVar2);
  piVar4 = (int *)0xc1f8b588;
  *(undefined4 *)((uint)aiStack_40 | 4) = 0;
  sVar6 = 0;
  do {
    if ((char)sVar6 < '\x16') {
      sVar7 = 0;
    }
    else {
      sVar7 = -1;
    }
    if (sVar7 != 0) goto LAB_c1736710;
    uVar5 = (uint)(char)sVar6;
    sVar7 = *(sbyte *)((int)piVar4 + uVar5 * 8 + 4);
    if (psVar2[1] == sVar7) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 != 0) {
      piVar4 = aiStack_40;
    }
    sVar6 = sVar6 + 1;
  } while (psVar2[1] != sVar7);
  *(undefined4 *)((uint)piVar4 | 4) = *(undefined4 *)(uVar5 * 8 + -0x3e074a78);
LAB_c1736710:
  if (*psVar2 == 5) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
    uStack_34 = *(undefined4 *)(psVar2 + 8);
    puStack_30 = *(undefined1 **)(psVar2 + 0xc);
    iVar3 = func_0xc1736804(aiStack_40);
    goto LAB_c17367c0;
  }
  uStack_38 = 0;
  sVar6 = 0;
  do {
    if ((char)sVar6 < '\f') {
      sVar7 = 0;
    }
    else {
      sVar7 = -1;
    }
    if (sVar7 != 0) goto LAB_c173674c;
    uVar5 = (uint)(char)sVar6;
    sVar6 = sVar6 + 1;
  } while (*(short *)(psVar2 + 2) != *(short *)(uVar5 * 8 + -0x3e074b04));
  uStack_38 = *(undefined4 *)(uVar5 * 8 + -0x3e074b08);
LAB_c173674c:
  sVar6 = psVar2[1] & 0xf0;
  uStack_34 = uStack_38;
  if (sVar6 == -0x70) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
  }
  else if (sVar6 == 0x20) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
  }
  else {
    if (psVar2[1] != 0x41) {
      uStack_38 = 0;
    }
    uStack_34 = 0;
  }
  puStack_30 = (undefined1 *)0x0;
  if (((*psVar2 == 3) && (sVar6 == 0x20)) && (*(int *)(psVar2 + 8) != 0)) {
    puStack_30 = auStack_28;
  }
  iVar3 = func_0xc1736804(aiStack_40);
  goto LAB_c17367c0;
}



======================================================================
[dispatch_table_lookup] FUN_c1736674 @ 0xC1736674 (400 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: stack */

int FUN_c1736674(int param_1,undefined4 param_2)

{
  int *piVar1;
  sbyte *psVar2;
  int iVar3;
  int extraout_r1;
  int *piVar4;
  uint uVar5;
  int in_GP;
  sbyte sVar6;
  sbyte sVar7;
  sbyte sVar8;
  int aiStack_40 [2];
  undefined4 uStack_38;
  undefined4 uStack_34;
  undefined1 *puStack_30;
  undefined1 auStack_28 [12];
  int iStack_1c;
  
  if (param_1 == 0) {
    sVar6 = -1;
  }
  else {
    sVar6 = 0;
  }
  if (sVar6 == 0) {
    *(undefined4 *)(param_1 + 0x14) = param_2;
    return param_1;
  }
  psVar2 = (sbyte *)func_0xc10db594(0xc3478b10);
  if (extraout_r1 == 0) {
    sVar6 = -1;
  }
  else {
    sVar6 = 0;
  }
  iStack_1c = **(int **)(in_GP + 20000);
  if ((sVar6 != 0) || (psVar2 == (sbyte *)0x0)) {
    while( true ) {
      iVar3 = 1;
      func_0xc13e477c(0xc1bf43a4);
LAB_c17367c0:
      if (**(int **)(in_GP + 20000) == iStack_1c) break;
      func_0xc1801040();
    }
    return iVar3;
  }
  piVar4 = (int *)0xc1f8b648;
  do {
    if (*piVar4 == 0) break;
    piVar1 = piVar4 + 1;
    if ((sbyte)*piVar1 == *psVar2) {
      sVar6 = -1;
    }
    else {
      sVar6 = 0;
    }
    if (sVar6 != 0) {
      aiStack_40[0] = *piVar4;
    }
    piVar4 = piVar4 + 2;
  } while ((sbyte)*piVar1 != *psVar2);
  piVar4 = (int *)0xc1f8b588;
  *(undefined4 *)((uint)aiStack_40 | 4) = 0;
  sVar6 = 0;
  do {
    if ((char)sVar6 < '\x16') {
      sVar7 = 0;
    }
    else {
      sVar7 = -1;
    }
    if (sVar7 != 0) goto LAB_c1736710;
    uVar5 = (uint)(char)sVar6;
    sVar7 = *(sbyte *)((int)piVar4 + uVar5 * 8 + 4);
    if (psVar2[1] == sVar7) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 != 0) {
      piVar4 = aiStack_40;
    }
    sVar6 = sVar6 + 1;
  } while (psVar2[1] != sVar7);
  *(undefined4 *)((uint)piVar4 | 4) = *(undefined4 *)(uVar5 * 8 + -0x3e074a78);
LAB_c1736710:
  if (*psVar2 == 5) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
    uStack_34 = *(undefined4 *)(psVar2 + 8);
    puStack_30 = *(undefined1 **)(psVar2 + 0xc);
    iVar3 = func_0xc1736804(aiStack_40);
    goto LAB_c17367c0;
  }
  uStack_38 = 0;
  sVar6 = 0;
  do {
    if ((char)sVar6 < '\f') {
      sVar7 = 0;
    }
    else {
      sVar7 = -1;
    }
    if (sVar7 != 0) goto LAB_c173674c;
    uVar5 = (uint)(char)sVar6;
    sVar6 = sVar6 + 1;
  } while (*(short *)(psVar2 + 2) != *(short *)(uVar5 * 8 + -0x3e074b04));
  uStack_38 = *(undefined4 *)(uVar5 * 8 + -0x3e074b08);
LAB_c173674c:
  sVar6 = psVar2[1] & 0xf0;
  uStack_34 = uStack_38;
  if (sVar6 == -0x70) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
  }
  else if (sVar6 == 0x20) {
    uStack_38 = *(undefined4 *)(psVar2 + 4);
  }
  else {
    if (psVar2[1] != 0x41) {
      uStack_38 = 0;
    }
    uStack_34 = 0;
  }
  puStack_30 = (undefined1 *)0x0;
  if (((*psVar2 == 3) && (sVar6 == 0x20)) && (*(int *)(psVar2 + 8) != 0)) {
    puStack_30 = auStack_28;
  }
  iVar3 = func_0xc1736804(aiStack_40);
  goto LAB_c17367c0;
}



======================================================================
[state_machine] FUN_c1735ed4 @ 0xC1735ED4 (1396 bytes)
======================================================================

/* WARNING: Possible PIC construction at 0xc1735f44: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc1736068: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17360a4: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17362e0: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17363bc: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17363e4: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc17363c8) */
/* WARNING: Removing unreachable block (ram,0xc17363cc) */
/* WARNING: Removing unreachable block (ram,0xc17363f8) */
/* WARNING: Removing unreachable block (ram,0xc1736400) */
/* WARNING: Removing unreachable block (ram,0xc173640c) */
/* WARNING: Removing unreachable block (ram,0xc1736424) */
/* WARNING: Removing unreachable block (ram,0xc17362e4) */
/* WARNING: Removing unreachable block (ram,0xc17360ac) */
/* WARNING: Removing unreachable block (ram,0xc17360c4) */
/* WARNING: Removing unreachable block (ram,0xc17360cc) */
/* WARNING: Removing unreachable block (ram,0xc17360e8) */
/* WARNING: Removing unreachable block (ram,0xc173606c) */
/* WARNING: Removing unreachable block (ram,0xc173607c) */
/* WARNING: Removing unreachable block (ram,0xc1736084) */
/* WARNING: Removing unreachable block (ram,0xc1736098) */
/* WARNING: Removing unreachable block (ram,0xc17360a4) */
/* WARNING: Removing unreachable block (ram,0xc17360fc) */
/* WARNING: Removing unreachable block (ram,0xc1735f48) */
/* WARNING: Removing unreachable block (ram,0xc17363f4) */
/* WARNING: Removing unreachable block (ram,0xc1736430) */
/* WARNING: Heritage AFTER dead removal. Example location: r1 : 0xc173604c */
/* WARNING: Restarted to delay deadcode elimination for space: register */

int FUN_c1735ed4(int *param_1,undefined4 param_2,code *param_3)

{
  int *piVar1;
  int *piVar2;
  undefined4 uVar3;
  undefined4 uVar4;
  int *piVar5;
  code *extraout_r1;
  code *extraout_r1_00;
  undefined4 extraout_r1_01;
  undefined4 extraout_r1_02;
  code *extraout_r1_03;
  code *pcVar6;
  code *extraout_r1_04;
  code *extraout_r1_05;
  code *pcVar7;
  int iVar8;
  undefined4 unaff_r19;
  undefined4 uVar9;
  sbyte unaff_r20;
  int iVar10;
  undefined1 *puVar11;
  undefined1 *puVar12;
  undefined4 uVar13;
  sbyte sVar14;
  undefined1 *puVar15;
  int *piVar16;
  int aiStack_c0 [20];
  undefined1 auStack_70 [16];
  undefined1 auStack_60 [40];
  
  if (param_1 == (int *)0x0) {
    piVar2 = (int *)func_0xc10db594(0xc347894e);
    pcVar7 = param_3;
    param_3 = extraout_r1_00;
  }
  else {
    pcVar7 = param_3;
    piVar1 = (int *)func_0xc1735f64();
    if (piVar1 == (int *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    piVar2 = piVar1;
    if (sVar14 != 0) {
      piVar2 = (int *)*param_1;
      param_3 = extraout_r1;
    }
    if (piVar1 == (int *)0x0) {
      if (*(code **)(*piVar2 + 0x20) == (code *)0x0) {
        func_0xc13e4c88();
      }
      else {
        (**(code **)(*piVar2 + 0x20))();
      }
      return -2;
    }
  }
  uVar3 = 0xc3478958;
  if (piVar2 != (int *)0x0) {
    uVar3 = 0xc3478962;
    if (((int *)*piVar2 != (int *)0x0) && (uVar3 = 0xc347896c, *(int *)*piVar2 != 0)) {
      uVar9 = 0xc1f8b3d2;
      sVar14 = func_0xc1736118(piVar2);
      if (sVar14 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar7 = *(code **)(*(int *)*piVar2 + 0x20);
        if (pcVar7 == (code *)0x0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          unaff_r20 = -1;
        }
        if (pcVar7 == (code *)0x0) {
          func_0xc13e4c88(0xc1bf42e4);
          unaff_r20 = -1;
        }
        else {
          (*pcVar7)();
        }
LAB_c1736104:
        return (int)unaff_r20;
      }
      if (piVar2[1] != -2) {
        func_0xc1736120(piVar2);
        unaff_r20 = 0;
        goto LAB_c1736104;
      }
      piVar1 = (int *)*piVar2;
      uVar3 = 0xc3478b88;
      piVar2[3] = 0;
      iVar8 = *piVar1;
      piVar2[2] = -0x81;
      unaff_r19 = 0xc1f8b3d2;
      if (piVar1 != (int *)0x0) {
        iVar10 = *piVar1;
        uVar3 = 0xc3478b92;
        if (iVar10 == 0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          pcVar7 = *(code **)(iVar10 + 0x18);
        }
        unaff_r19 = 0xc1f8b3d2;
        if (iVar10 != 0) {
          if (pcVar7 != (code *)0x0) {
            (*pcVar7)();
          }
          if (*(code **)(iVar10 + 0x24) != (code *)0x0) {
            (**(code **)(iVar10 + 0x24))(0,param_3,piVar2[1],param_3);
          }
          uVar3 = 0xfe;
          piVar2[1] = *(int *)(iVar8 + 0x28);
          goto SUB_c1736130;
        }
      }
    }
  }
  uVar9 = unaff_r19;
  param_3 = pcVar7;
  piVar2 = (int *)func_0xc10db594(uVar3);
  uVar3 = extraout_r1_01;
SUB_c1736130:
  uVar4 = 0xc3478b6a;
  if (piVar2 != (int *)0x0) {
    uVar4 = 0xc3478b74;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar8 = *(int *)*piVar2;
      uVar4 = 0xc3478b7e;
      if (iVar8 != 0) {
        iVar10 = *(int *)(iVar8 + 8) + piVar2[1] * 0x10;
        if (*(code **)(iVar10 + 4) != (code *)0x0) {
          iVar10 = (**(code **)(iVar10 + 4))(piVar2,uVar3,param_3);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          iVar10 = (**(code **)(iVar8 + 0x24))();
        }
        return iVar10;
      }
      uVar9 = 0;
    }
  }
  piVar1 = (int *)func_0xc10db594(uVar4);
  puVar12 = auStack_60;
  puVar11 = auStack_70;
  uVar3 = 0xc3478b4c;
  if (piVar1 != (int *)0x0) {
    uVar3 = 0xc3478b56;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar8 = *(int *)*piVar1;
      uVar3 = 0xc3478b60;
      if (iVar8 != 0) {
        iVar10 = *(int *)(iVar8 + 8) + piVar1[1] * 0x10;
        if (*(code **)(iVar10 + 8) != (code *)0x0) {
          iVar10 = (**(code **)(iVar10 + 8))(piVar1,extraout_r1_02,param_3);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          iVar10 = (**(code **)(iVar8 + 0x24))();
        }
        return iVar10;
      }
      uVar9 = 0;
    }
  }
  uVar4 = 0xc173620c;
  pcVar7 = param_3;
  piVar2 = (int *)func_0xc10db594(uVar3);
  uVar3 = extraout_r1_02;
  pcVar6 = extraout_r1_03;
SUB_c1736210:
  *(undefined4 *)(puVar11 + -4) = uVar4;
  *(undefined1 **)(puVar11 + -8) = puVar12;
  *(int **)(puVar11 + -0x10) = piVar1;
  *(code **)(puVar11 + -0xc) = param_3;
  *(undefined4 *)(puVar11 + -0x18) = uVar3;
  *(undefined4 *)(puVar11 + -0x14) = uVar9;
  uVar4 = 0xc3478b2e;
  if (piVar2 != (int *)0x0) {
    uVar4 = 0xc3478b38;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar10 = *(int *)*piVar2;
      iVar8 = -0x3cb874be;
      uVar4 = 0xc3478b42;
      if (iVar10 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar7 = *(code **)(iVar10 + 0x1c);
      }
      if (iVar10 != 0) {
        if (pcVar7 != (code *)0x0) {
          iVar8 = (*pcVar7)();
        }
        if (*(code **)(iVar10 + 0x24) != (code *)0x0) {
          iVar8 = (**(code **)(iVar10 + 0x24))(2,pcVar6,piVar2[1],pcVar6);
        }
        return iVar8;
      }
      uVar3 = 0;
    }
  }
  uVar13 = 0xc1736270;
  piVar5 = (int *)func_0xc10db594(uVar4);
  piVar16 = (int *)(puVar11 + -0x20);
  *(undefined4 *)(puVar11 + -0x1c) = uVar13;
  *piVar16 = (int)(puVar11 + -8);
  *(int **)(puVar11 + -0x28) = piVar2;
  *(code **)(puVar11 + -0x24) = pcVar6;
  if (piVar5 == (int *)0x0) {
    uVar4 = 0xc17362fc;
    piVar1 = (int *)func_0xc10db594(0xc3478976);
    puVar15 = puVar11 + -0x30;
    param_3 = extraout_r1_05;
  }
  else {
    piVar2 = (int *)func_0xc1735f64(piVar5);
    if (piVar2 == (int *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    piVar1 = piVar2;
    param_3 = pcVar7;
    if (sVar14 != 0) {
      piVar1 = (int *)*piVar5;
      param_3 = extraout_r1_04;
    }
    if (piVar2 == (int *)0x0) 

  [... truncated, 10603 chars total ...]

======================================================================
[generic_handler] FUN_c1735ed4 @ 0xC1735ED4 (1396 bytes)
======================================================================

/* WARNING: Possible PIC construction at 0xc1735f44: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc1736068: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17360a4: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17362e0: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17363bc: Changing call to branch */
/* WARNING: Possible PIC construction at 0xc17363e4: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc17363c8) */
/* WARNING: Removing unreachable block (ram,0xc17363cc) */
/* WARNING: Removing unreachable block (ram,0xc17363f8) */
/* WARNING: Removing unreachable block (ram,0xc1736400) */
/* WARNING: Removing unreachable block (ram,0xc173640c) */
/* WARNING: Removing unreachable block (ram,0xc1736424) */
/* WARNING: Removing unreachable block (ram,0xc17362e4) */
/* WARNING: Removing unreachable block (ram,0xc17360ac) */
/* WARNING: Removing unreachable block (ram,0xc17360c4) */
/* WARNING: Removing unreachable block (ram,0xc17360cc) */
/* WARNING: Removing unreachable block (ram,0xc17360e8) */
/* WARNING: Removing unreachable block (ram,0xc173606c) */
/* WARNING: Removing unreachable block (ram,0xc173607c) */
/* WARNING: Removing unreachable block (ram,0xc1736084) */
/* WARNING: Removing unreachable block (ram,0xc1736098) */
/* WARNING: Removing unreachable block (ram,0xc17360a4) */
/* WARNING: Removing unreachable block (ram,0xc17360fc) */
/* WARNING: Removing unreachable block (ram,0xc1735f48) */
/* WARNING: Removing unreachable block (ram,0xc17363f4) */
/* WARNING: Removing unreachable block (ram,0xc1736430) */
/* WARNING: Heritage AFTER dead removal. Example location: r1 : 0xc173604c */
/* WARNING: Restarted to delay deadcode elimination for space: register */

int FUN_c1735ed4(int *param_1,undefined4 param_2,code *param_3)

{
  int *piVar1;
  int *piVar2;
  undefined4 uVar3;
  undefined4 uVar4;
  int *piVar5;
  code *extraout_r1;
  code *extraout_r1_00;
  undefined4 extraout_r1_01;
  undefined4 extraout_r1_02;
  code *extraout_r1_03;
  code *pcVar6;
  code *extraout_r1_04;
  code *extraout_r1_05;
  code *pcVar7;
  int iVar8;
  undefined4 unaff_r19;
  undefined4 uVar9;
  sbyte unaff_r20;
  int iVar10;
  undefined1 *puVar11;
  undefined1 *puVar12;
  undefined4 uVar13;
  sbyte sVar14;
  undefined1 *puVar15;
  int *piVar16;
  int aiStack_c0 [20];
  undefined1 auStack_70 [16];
  undefined1 auStack_60 [40];
  
  if (param_1 == (int *)0x0) {
    piVar2 = (int *)func_0xc10db594(0xc347894e);
    pcVar7 = param_3;
    param_3 = extraout_r1_00;
  }
  else {
    pcVar7 = param_3;
    piVar1 = (int *)func_0xc1735f64();
    if (piVar1 == (int *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    piVar2 = piVar1;
    if (sVar14 != 0) {
      piVar2 = (int *)*param_1;
      param_3 = extraout_r1;
    }
    if (piVar1 == (int *)0x0) {
      if (*(code **)(*piVar2 + 0x20) == (code *)0x0) {
        func_0xc13e4c88();
      }
      else {
        (**(code **)(*piVar2 + 0x20))();
      }
      return -2;
    }
  }
  uVar3 = 0xc3478958;
  if (piVar2 != (int *)0x0) {
    uVar3 = 0xc3478962;
    if (((int *)*piVar2 != (int *)0x0) && (uVar3 = 0xc347896c, *(int *)*piVar2 != 0)) {
      uVar9 = 0xc1f8b3d2;
      sVar14 = func_0xc1736118(piVar2);
      if (sVar14 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar7 = *(code **)(*(int *)*piVar2 + 0x20);
        if (pcVar7 == (code *)0x0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          unaff_r20 = -1;
        }
        if (pcVar7 == (code *)0x0) {
          func_0xc13e4c88(0xc1bf42e4);
          unaff_r20 = -1;
        }
        else {
          (*pcVar7)();
        }
LAB_c1736104:
        return (int)unaff_r20;
      }
      if (piVar2[1] != -2) {
        func_0xc1736120(piVar2);
        unaff_r20 = 0;
        goto LAB_c1736104;
      }
      piVar1 = (int *)*piVar2;
      uVar3 = 0xc3478b88;
      piVar2[3] = 0;
      iVar8 = *piVar1;
      piVar2[2] = -0x81;
      unaff_r19 = 0xc1f8b3d2;
      if (piVar1 != (int *)0x0) {
        iVar10 = *piVar1;
        uVar3 = 0xc3478b92;
        if (iVar10 == 0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          pcVar7 = *(code **)(iVar10 + 0x18);
        }
        unaff_r19 = 0xc1f8b3d2;
        if (iVar10 != 0) {
          if (pcVar7 != (code *)0x0) {
            (*pcVar7)();
          }
          if (*(code **)(iVar10 + 0x24) != (code *)0x0) {
            (**(code **)(iVar10 + 0x24))(0,param_3,piVar2[1],param_3);
          }
          uVar3 = 0xfe;
          piVar2[1] = *(int *)(iVar8 + 0x28);
          goto SUB_c1736130;
        }
      }
    }
  }
  uVar9 = unaff_r19;
  param_3 = pcVar7;
  piVar2 = (int *)func_0xc10db594(uVar3);
  uVar3 = extraout_r1_01;
SUB_c1736130:
  uVar4 = 0xc3478b6a;
  if (piVar2 != (int *)0x0) {
    uVar4 = 0xc3478b74;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar8 = *(int *)*piVar2;
      uVar4 = 0xc3478b7e;
      if (iVar8 != 0) {
        iVar10 = *(int *)(iVar8 + 8) + piVar2[1] * 0x10;
        if (*(code **)(iVar10 + 4) != (code *)0x0) {
          iVar10 = (**(code **)(iVar10 + 4))(piVar2,uVar3,param_3);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          iVar10 = (**(code **)(iVar8 + 0x24))();
        }
        return iVar10;
      }
      uVar9 = 0;
    }
  }
  piVar1 = (int *)func_0xc10db594(uVar4);
  puVar12 = auStack_60;
  puVar11 = auStack_70;
  uVar3 = 0xc3478b4c;
  if (piVar1 != (int *)0x0) {
    uVar3 = 0xc3478b56;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar8 = *(int *)*piVar1;
      uVar3 = 0xc3478b60;
      if (iVar8 != 0) {
        iVar10 = *(int *)(iVar8 + 8) + piVar1[1] * 0x10;
        if (*(code **)(iVar10 + 8) != (code *)0x0) {
          iVar10 = (**(code **)(iVar10 + 8))(piVar1,extraout_r1_02,param_3);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          iVar10 = (**(code **)(iVar8 + 0x24))();
        }
        return iVar10;
      }
      uVar9 = 0;
    }
  }
  uVar4 = 0xc173620c;
  pcVar7 = param_3;
  piVar2 = (int *)func_0xc10db594(uVar3);
  uVar3 = extraout_r1_02;
  pcVar6 = extraout_r1_03;
SUB_c1736210:
  *(undefined4 *)(puVar11 + -4) = uVar4;
  *(undefined1 **)(puVar11 + -8) = puVar12;
  *(int **)(puVar11 + -0x10) = piVar1;
  *(code **)(puVar11 + -0xc) = param_3;
  *(undefined4 *)(puVar11 + -0x18) = uVar3;
  *(undefined4 *)(puVar11 + -0x14) = uVar9;
  uVar4 = 0xc3478b2e;
  if (piVar2 != (int *)0x0) {
    uVar4 = 0xc3478b38;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar10 = *(int *)*piVar2;
      iVar8 = -0x3cb874be;
      uVar4 = 0xc3478b42;
      if (iVar10 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar7 = *(code **)(iVar10 + 0x1c);
      }
      if (iVar10 != 0) {
        if (pcVar7 != (code *)0x0) {
          iVar8 = (*pcVar7)();
        }
        if (*(code **)(iVar10 + 0x24) != (code *)0x0) {
          iVar8 = (**(code **)(iVar10 + 0x24))(2,pcVar6,piVar2[1],pcVar6);
        }
        return iVar8;
      }
      uVar3 = 0;
    }
  }
  uVar13 = 0xc1736270;
  piVar5 = (int *)func_0xc10db594(uVar4);
  piVar16 = (int *)(puVar11 + -0x20);
  *(undefined4 *)(puVar11 + -0x1c) = uVar13;
  *piVar16 = (int)(puVar11 + -8);
  *(int **)(puVar11 + -0x28) = piVar2;
  *(code **)(puVar11 + -0x24) = pcVar6;
  if (piVar5 == (int *)0x0) {
    uVar4 = 0xc17362fc;
    piVar1 = (int *)func_0xc10db594(0xc3478976);
    puVar15 = puVar11 + -0x30;
    param_3 = extraout_r1_05;
  }
  else {
    piVar2 = (int *)func_0xc1735f64(piVar5);
    if (piVar2 == (int *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    piVar1 = piVar2;
    param_3 = pcVar7;
    if (sVar14 != 0) {
      piVar1 = (int *)*piVar5;
      param_3 = extraout_r1_04;
    }
    if (piVar2 == (int *)0x0) 

  [... truncated, 10603 chars total ...]

======================================================================
[mmgsdi_async_callback] FUN_c09caa78 @ 0xC09CAA78 (288 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: register */

undefined4 FUN_c09caa78(int param_1,int param_2)

{
  sbyte sVar1;
  int iVar2;
  int iVar3;
  undefined4 uVar4;
  int iVar5;
  int in_GP;
  
  if (param_2 != 0) {
    func_0xc0a23140(param_1);
    func_0xc093b13c();
    sVar1 = func_0xc092a1e4(0xc2149db0,param_1,0);
    if (sVar1 == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    uVar4 = 0xc344f2cc;
    if (sVar1 == 0) goto LAB_c09cab74;
    *(undefined1 *)(*(int *)(param_1 * 4 + -0x3d25ade8) + 0x194) = 0;
    *(undefined1 *)(*(int *)(param_1 * 4 + -0x3d25ade8) + 0x19c) = 0;
    if (**(sbyte **)(in_GP + 0x266) != 1) {
      if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
        sVar1 = -1;
      }
      else {
        sVar1 = 0;
      }
      if (sVar1 != 0) goto LAB_c09cab5c;
      if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
        sVar1 = -1;
      }
      else {
        sVar1 = 0;
      }
      if (sVar1 != 0) goto LAB_c09cab5c;
    }
    func_0xc0bde25c(0xc1b669b0);
    goto LAB_c09cab5c;
  }
  sVar1 = func_0xc09cab80();
  if (sVar1 == 0) {
    sVar1 = -1;
  }
  else {
    sVar1 = 0;
  }
  uVar4 = 0xc344f2d6;
  if (sVar1 == 0) {
LAB_c09cab74:
    iVar2 = func_0xc10db594(uVar4);
    iVar5 = -0x3e20e5d6;
    iVar2 = *(int *)(iVar2 * 4 + -0x3d25ade8);
    if (iVar2 == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    if (sVar1 == 0) {
      iVar5 = 0x2f;
    }
    if (iVar2 != 0) {
      uVar4 = 0xc3444ff2;
      iVar3 = *(int *)(iVar2 + -0x18);
      if (iVar3 == iVar5) {
        uVar4 = 0xc3444ffc;
        iVar3 = *(int *)(iVar2 + -8);
        if (iVar3 == 0) {
          uVar4 = 0xc3445006;
          iVar3 = *(int *)(iVar2 + -4);
          if (iVar3 == 0x1234567) {
            func_0xc0920810();
            uVar4 = **(undefined4 **)(in_GP + 0xd4f0);
            *(undefined4 *)(iVar2 + -4) = uVar4;
            *(undefined4 *)(iVar2 + -0x18) = uVar4;
            uVar4 = func_0xc071719c();
            return uVar4;
          }
        }
      }
      func_0xc10db594(uVar4,iVar3,iVar5,0x3a4);
    }
    uVar4 = func_0xc0bde2c8();
    return uVar4;
  }
  if (**(sbyte **)(in_GP + 0x266) != 1) {
    if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    if (sVar1 != 0) goto LAB_c09cab5c;
    if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    if (sVar1 != 0) goto LAB_c09cab5c;
  }
  func_0xc0bde25c(0xc1b669b8);
LAB_c09cab5c:
  **(undefined1 **)(param_1 * 4 + -0x3d25ade8) = 0;
  return 1;
}



======================================================================
[lpa_main_handler] FUN_c0f1173c @ 0xC0F1173C (24 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */
/* WARNING: Possible PIC construction at 0xc0f11808: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc0f11810) */
/* WARNING: Removing unreachable block (ram,0xc0f1181c) */
/* WARNING: Removing unreachable block (ram,0xc0f11850) */
/* WARNING: Removing unreachable block (ram,0xc0f11854) */
/* WARNING: Restarted to delay deadcode elimination for space: register */

void FUN_c0f1173c(undefined4 param_1,undefined4 param_2,undefined4 param_3)

{
  sbyte sVar1;
  uint uVar2;
  undefined4 *puVar3;
  undefined1 *puVar4;
  sbyte *psVar5;
  undefined4 uVar6;
  code *extraout_r1;
  int iVar7;
  undefined4 unaff_r20;
  undefined4 unaff_r21;
  int *piVar8;
  int in_GP;
  sbyte sVar9;
  undefined4 uStack_a8;
  undefined1 uStack_a4;
  undefined1 *puStack_a0;
  uint uStack_9c;
  undefined1 auStack_98 [12];
  undefined4 uStack_8c;
  undefined4 uStack_88;
  undefined1 auStack_80 [23];
  undefined1 uStack_69;
  undefined1 auStack_68 [28];
  code *pcStack_4c;
  undefined4 uStack_48;
  undefined4 uStack_30;
  int iStack_2c;
  
  uVar2 = func_0xc0f10514();
  iStack_2c = **(int **)(in_GP + 20000);
  uStack_69 = 10;
  uStack_30 = 0x7fffffff;
  thunk_EXT_FUN_c070df10(auStack_80,0xc1cd0678);
  thunk_EXT_FUN_c070e4e0(auStack_68,0);
  if (uVar2 < 2) {
    if (*(longlong *)(uVar2 * 8 + -0x3d811d98) == CONCAT44(unaff_r21,unaff_r20)) {
      sVar9 = -1;
    }
    else {
      sVar9 = 0;
    }
    if (sVar9 == 0) {
      func_0xc0bde2c8();
      (*extraout_r1)(0,0,param_3);
    }
    else {
      *(sbyte *)((uint)auStack_68 | 3) = (sbyte)uVar2;
      pcStack_4c = extraout_r1;
      uStack_48 = param_3;
      puVar4 = (undefined1 *)FUN_c0f12d14(uVar2,&uStack_30);
      if (puVar4 == (undefined1 *)0x0) {
        sVar9 = -1;
      }
      else {
        sVar9 = 0;
      }
      puVar3 = (undefined4 *)puVar4;
      if (sVar9 != 0) {
        puVar3 = &uStack_a8;
      }
      if (puVar4 == (undefined1 *)0x0) {
        *(uint *)((uint)&stack0xffffffc0 | 4) = (uint)auStack_80 | 1;
        thunk_EXT_FUN_c070df10(puVar3,auStack_68);
        puVar4 = &uStack_69;
        goto SUB_c0f11890;
      }
    }
  }
  if (**(int **)(in_GP + 20000) == iStack_2c) {
                    /* WARNING: Bad instruction - Truncating control flow here */
    halt_baddata();
  }
  puVar4 = (undefined1 *)func_0xc08f9b60();
SUB_c0f11890:
  psVar5 = (sbyte *)thunk_EXT_FUN_c070dd00(puVar4);
  if (psVar5 != (sbyte *)0x0) {
    func_0xc0bde33c(0xc1a626c8,uStack_a8 & 0xff,uStack_a8 >> 8 & 0xff);
    sVar9 = 0;
    do {
      sVar1 = sVar9;
      if ((char)sVar1 < '\n') {
        sVar9 = 0;
      }
      else {
        sVar9 = -1;
      }
      uVar2 = (uint)(char)sVar1;
    } while ((sVar9 == 0) && (sVar9 = sVar1 + 1, *(int *)(uVar2 * 4 + -0x3d811d70) != 0));
    if (sVar1 == 10) {
      sVar9 = -1;
    }
    else {
      sVar9 = 0;
    }
    if (sVar9 == 0) {
      puVar4 = (undefined1 *)func_0xc0f12bb0(0x24);
      *(undefined1 **)(uVar2 * 4 + -0x3d811d70) = puVar4;
      if (puVar4 != (undefined1 *)0x0) {
        piVar8 = (int *)(uVar2 * 4 + -0x3d811d70);
        if (puStack_a0 == (undefined1 *)0x0) {
          sVar9 = -1;
        }
        else {
          sVar9 = 0;
        }
        if (sVar9 == 0) {
          uVar2 = uStack_9c;
        }
        if (puStack_a0 != (undefined1 *)0x0) {
          if (uVar2 == 0) {
            sVar9 = -1;
          }
          else {
            sVar9 = 0;
          }
          if (sVar9 == 0) {
            puVar4 = puStack_a0;
          }
          if (uVar2 != 0) {
            uVar6 = func_0xc0f12ba4();
            *(undefined4 *)(*piVar8 + 0xc) = uVar6;
            iVar7 = *(int *)(*piVar8 + 0xc);
            if (iVar7 == 0) {
              sVar9 = -1;
            }
            else {
              sVar9 = 0;
            }
            if (sVar9 == 0) {
              *(undefined1 **)(*piVar8 + 8) = puStack_a0;
            }
            if (iVar7 == 0) {
              halt_baddata();
            }
            func_0xc0714250(*(undefined4 *)(*piVar8 + 0xc),*(undefined4 *)(*piVar8 + 8));
            puVar4 = (undefined1 *)*piVar8;
          }
        }
        *puVar4 = (sbyte)uStack_a8;
        *(undefined1 *)(*piVar8 + 3) = 0;
        *(undefined1 *)(*piVar8 + 1) = uStack_a8._1_1_;
        *(undefined1 *)(*piVar8 + 2) = 0;
        *(undefined1 *)(*piVar8 + 4) = uStack_a4;
        thunk_EXT_FUN_c070df10(*piVar8 + 0x10,auStack_98);
        *(undefined4 *)(*piVar8 + 0x1c) = uStack_8c;
        iVar7 = *piVar8;
        *psVar5 = sVar1;
        *(undefined4 *)(iVar7 + 0x20) = uStack_88;
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
[validate_table_lookup] FUN_c071a6c4 @ 0xC071A6C4 (288 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: register */

int * FUN_c071a6c4(int *param_1,uint param_2)

{
  short sVar1;
  int iVar2;
  int *extraout_r1;
  undefined *puVar3;
  int *piVar4;
  int iVar5;
  int *piVar6;
  int iVar7;
  uint uVar8;
  int iVar9;
  int iVar10;
  int iVar11;
  int iVar12;
  int unaff_r21;
  sbyte sVar13;
  short sVar14;
  
  puVar3 = &UNK_c3478a2a;
  if (param_1 != (int *)0x0) {
    piVar6 = (int *)*param_1;
    puVar3 = &UNK_c3478a34;
    if (piVar6 != (int *)0x0) {
      puVar3 = &UNK_c3478a3e;
      if ((uint *)*piVar6 != (uint *)0x0) {
        uVar8 = *(uint *)*piVar6;
        piVar4 = (int *)0x0;
        if (param_2 < uVar8) {
          sVar13 = -1;
        }
        else {
          sVar13 = 0;
        }
        if (sVar13 != 0) {
          piVar4 = (int *)piVar6[3];
        }
        if (param_2 < uVar8) {
          piVar4 = param_1 + (param_2 - (int)piVar4) * 7;
        }
        return piVar4;
      }
    }
  }
  func_0xc0712140(puVar3);
  iVar2 = __save_r16_through_r21();
  iVar12 = extraout_r1[6];
  iVar10 = extraout_r1[4];
  iVar9 = *(int *)(iVar2 + 8);
  if (iVar12 < 1) {
    unaff_r21 = extraout_r1[7];
  }
  sVar1 = *(short *)(iVar2 + 0x28);
  if (iVar12 < 1) {
    if (0 < (int)puVar3) {
      uVar8 = USR;
      USR = uVar8 & 0xfffffcff;
      piVar6 = (int *)extraout_r1[8];
      iVar11 = iVar10;
      while( true ) {
        iVar10 = iVar11 + 1;
        iVar5 = *piVar6;
        *piVar6 = *(int *)(*extraout_r1 + iVar11 * 4);
        if (iVar9 < iVar10) {
          iVar10 = 0;
        }
        *(int *)(*extraout_r1 + iVar11 * 4) = iVar5;
        if (puVar3 < (undefined *)0x2) break;
        puVar3 = puVar3 + -1;
        piVar6 = (int *)((int)piVar6 + 2);
        iVar11 = iVar10;
      }
    }
  }
  else {
    iVar12 = mpy_sat((short)iVar12,0x6000);
    sVar14 = (short)((uint)(iVar12 << 1) >> 0x10);
    iVar12 = (int)sVar14;
    sVar14 = 0x7fff - sVar14;
    unaff_r21 = (int)sVar14;
    if (0 < (int)puVar3) {
      uVar8 = USR;
      USR = uVar8 & 0xfffffcff;
      piVar6 = (int *)extraout_r1[8];
      iVar11 = iVar10;
      while( true ) {
        iVar10 = iVar11 + 1;
        iVar7 = *piVar6;
        iVar5 = mpy_rnd_sat(*(undefined4 *)(*extraout_r1 + iVar11 * 4),sVar14);
        *piVar6 = iVar5 << 1;
        if (iVar9 < iVar10) {
          iVar10 = 0;
        }
        *(int *)(*extraout_r1 + iVar11 * 4) = iVar7;
        if (puVar3 < (undefined *)0x2) break;
        puVar3 = puVar3 + -1;
        piVar6 = (int *)((int)piVar6 + 2);
        iVar11 = iVar10;
      }
    }
  }
  piVar6 = (int *)extraout_r1[9];
  if (piVar6 == (int *)0x1) {
    piVar6 = (int *)memset(extraout_r1[1],0,(int)sVar1 << 2);
    extraout_r1[2] = 1;
    extraout_r1[3] = 0x7fff;
    extraout_r1[9] = 2;
  }
  extraout_r1[7] = unaff_r21;
  extraout_r1[6] = iVar12;
  *(int *)(iVar2 + 8) = iVar9;
  extraout_r1[4] = iVar10;
  return piVar6;
}




Done.
