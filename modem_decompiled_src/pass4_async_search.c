Pass 4: Async handler + ISD-R AID search

======================================================================
[async_process] FUN_c0a23140 @ 0xC0A23140 (12 bytes)
======================================================================

undefined4 FUN_c0a23140(int param_1)

{
  return *(undefined4 *)(&UNK_c2da5648 + param_1 * 4);
}



======================================================================
[session_mgr_1] FUN_c093b13c @ 0xC093B13C (8 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: stack */

int FUN_c093b13c(int param_1,undefined4 param_2)

{
  sbyte *psVar1;
  int *piVar2;
  sbyte *psVar3;
  int iVar4;
  int extraout_r1;
  int *piVar5;
  uint uVar6;
  int in_GP;
  sbyte sVar7;
  sbyte sVar8;
  int aiStack_40 [2];
  undefined4 uStack_38;
  undefined4 uStack_34;
  undefined1 *puStack_30;
  undefined1 auStack_28 [12];
  int iStack_1c;
  
  if (param_1 == 0) {
    sVar7 = -1;
  }
  else {
    sVar7 = 0;
  }
  if (sVar7 == 0) {
    *(undefined4 *)(param_1 + 0x14) = param_2;
    return param_1;
  }
  psVar3 = (sbyte *)func_0xc10db594(&UNK_c3478b10);
  if (extraout_r1 == 0) {
    sVar7 = -1;
  }
  else {
    sVar7 = 0;
  }
  iStack_1c = **(int **)(in_GP + 20000);
  if ((sVar7 != 0) || (psVar3 == (sbyte *)0x0)) {
    while( true ) {
      iVar4 = 1;
      func_0xc13e477c(&UNK_c1bf43a4);
code_r0xc17367c0:
      if (**(int **)(in_GP + 20000) == iStack_1c) break;
      func_0xc1801040();
    }
    return iVar4;
  }
  piVar5 = (int *)&UNK_c1f8b648;
  do {
    if (*piVar5 == 0) break;
    piVar2 = piVar5 + 1;
    if ((sbyte)*piVar2 == *psVar3) {
      sVar7 = -1;
    }
    else {
      sVar7 = 0;
    }
    if (sVar7 != 0) {
      aiStack_40[0] = *piVar5;
    }
    piVar5 = piVar5 + 2;
  } while ((sbyte)*piVar2 != *psVar3);
  piVar5 = (int *)&UNK_c1f8b588;
  *(undefined4 *)((uint)aiStack_40 | 4) = 0;
  sVar7 = 0;
  do {
    if ((char)sVar7 < '\x16') {
      sVar8 = 0;
    }
    else {
      sVar8 = -1;
    }
    if (sVar8 != 0) goto code_r0xc1736710;
    uVar6 = (uint)(char)sVar7;
    psVar1 = (sbyte *)((int)piVar5 + uVar6 * 8 + 4);
    if (psVar3[1] == *psVar1) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 != 0) {
      piVar5 = aiStack_40;
    }
    sVar7 = sVar7 + 1;
  } while (psVar3[1] != *psVar1);
  *(undefined4 *)((uint)piVar5 | 4) = *(undefined4 *)(&UNK_c1f8b588 + uVar6 * 8);
code_r0xc1736710:
  if (*psVar3 == 5) {
    uStack_38 = *(undefined4 *)(psVar3 + 4);
    uStack_34 = *(undefined4 *)(psVar3 + 8);
    puStack_30 = *(undefined1 **)(psVar3 + 0xc);
    iVar4 = func_0xc1736804(aiStack_40);
    goto code_r0xc17367c0;
  }
  uStack_38 = 0;
  sVar7 = 0;
  do {
    if ((char)sVar7 < '\f') {
      sVar8 = 0;
    }
    else {
      sVar8 = -1;
    }
    if (sVar8 != 0) goto code_r0xc173674c;
    uVar6 = (uint)(char)sVar7;
    sVar7 = sVar7 + 1;
  } while (*(short *)(psVar3 + 2) != *(short *)(&UNK_c1f8b4fc + uVar6 * 8));
  uStack_38 = *(undefined4 *)(&UNK_c1f8b4f8 + uVar6 * 8);
code_r0xc173674c:
  sVar7 = psVar3[1] & 0xf0;
  uStack_34 = uStack_38;
  if (sVar7 == -0x70) {
    uStack_38 = *(undefined4 *)(psVar3 + 4);
  }
  else if (sVar7 == 0x20) {
    uStack_38 = *(undefined4 *)(psVar3 + 4);
  }
  else {
    if (psVar3[1] != 0x41) {
      uStack_38 = 0;
    }
    uStack_34 = 0;
  }
  puStack_30 = (undefined1 *)0x0;
  if (((*psVar3 == 3) && (sVar7 == 0x20)) && (*(int *)(psVar3 + 8) != 0)) {
    puStack_30 = auStack_28;
  }
  iVar4 = func_0xc1736804(aiStack_40);
  goto code_r0xc17367c0;
}



======================================================================
[session_mgr_2] FUN_c092a1e4 @ 0xC092A1E4 (8 bytes)
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

undefined * FUN_c092a1e4(int *param_1,undefined4 param_2,code *param_3)

{
  int *piVar1;
  int *piVar2;
  undefined *puVar3;
  int *piVar4;
  code *extraout_r1;
  code *extraout_r1_00;
  undefined4 extraout_r1_01;
  undefined4 extraout_r1_02;
  code *extraout_r1_03;
  code *pcVar5;
  code *extraout_r1_04;
  code *extraout_r1_05;
  code *pcVar6;
  int iVar7;
  undefined4 uVar8;
  undefined *unaff_r19;
  undefined *puVar9;
  sbyte unaff_r20;
  int iVar10;
  undefined1 *puVar11;
  undefined1 *puVar12;
  undefined *puVar13;
  sbyte sVar14;
  undefined1 *puVar15;
  int *piVar16;
  int aiStack_c0 [20];
  undefined1 auStack_70 [16];
  undefined1 auStack_60 [40];
  
  if (param_1 == (int *)0x0) {
    piVar2 = (int *)func_0xc10db594(&UNK_c347894e);
    pcVar6 = param_3;
    param_3 = extraout_r1_00;
  }
  else {
    pcVar6 = param_3;
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
      return (undefined *)0xfffffffe;
    }
  }
  puVar3 = &UNK_c3478958;
  if (piVar2 != (int *)0x0) {
    puVar3 = &UNK_c3478962;
    if (((int *)*piVar2 != (int *)0x0) && (puVar3 = &UNK_c347896c, *(int *)*piVar2 != 0)) {
      puVar9 = &UNK_c1f8b3d2;
      sVar14 = func_0xc1736118(piVar2);
      if (sVar14 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar6 = *(code **)(*(int *)*piVar2 + 0x20);
        if (pcVar6 == (code *)0x0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          unaff_r20 = -1;
        }
        if (pcVar6 == (code *)0x0) {
          func_0xc13e4c88(&UNK_c1bf42e4);
          unaff_r20 = -1;
        }
        else {
          (*pcVar6)();
        }
code_r0xc1736104:
        return (undefined *)(int)unaff_r20;
      }
      if (piVar2[1] != -2) {
        func_0xc1736120(piVar2);
        unaff_r20 = 0;
        goto code_r0xc1736104;
      }
      piVar1 = (int *)*piVar2;
      puVar3 = &UNK_c3478b88;
      piVar2[3] = 0;
      iVar7 = *piVar1;
      piVar2[2] = -0x81;
      unaff_r19 = &UNK_c1f8b3d2;
      if (piVar1 != (int *)0x0) {
        iVar10 = *piVar1;
        puVar3 = &UNK_c3478b92;
        if (iVar10 == 0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) {
          pcVar6 = *(code **)(iVar10 + 0x18);
        }
        unaff_r19 = &UNK_c1f8b3d2;
        if (iVar10 != 0) {
          if (pcVar6 != (code *)0x0) {
            (*pcVar6)();
          }
          if (*(code **)(iVar10 + 0x24) != (code *)0x0) {
            (**(code **)(iVar10 + 0x24))(0,param_3,piVar2[1],param_3);
          }
          uVar8 = 0xfe;
          piVar2[1] = *(int *)(iVar7 + 0x28);
          goto code_r0xc1736130;
        }
      }
    }
  }
  puVar9 = unaff_r19;
  param_3 = pcVar6;
  piVar2 = (int *)func_0xc10db594(puVar3);
  uVar8 = extraout_r1_01;
code_r0xc1736130:
  puVar3 = &UNK_c3478b6a;
  if (piVar2 != (int *)0x0) {
    puVar3 = &UNK_c3478b74;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar7 = *(int *)*piVar2;
      puVar3 = &UNK_c3478b7e;
      if (iVar7 != 0) {
        puVar3 = (undefined *)(*(int *)(iVar7 + 8) + piVar2[1] * 0x10);
        if (*(code **)(puVar3 + 4) != (code *)0x0) {
          puVar3 = (undefined *)(**(code **)(puVar3 + 4))(piVar2,uVar8,param_3);
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar3 = (undefined *)(**(code **)(iVar7 + 0x24))();
        }
        return puVar3;
      }
      puVar9 = (undefined *)0x0;
    }
  }
  piVar1 = (int *)func_0xc10db594(puVar3);
  puVar12 = auStack_60;
  puVar11 = auStack_70;
  puVar3 = &UNK_c3478b4c;
  if (piVar1 != (int *)0x0) {
    puVar3 = &UNK_c3478b56;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar7 = *(int *)*piVar1;
      puVar3 = &UNK_c3478b60;
      if (iVar7 != 0) {
        puVar3 = (undefined *)(*(int *)(iVar7 + 8) + piVar1[1] * 0x10);
        if (*(code **)(puVar3 + 8) != (code *)0x0) {
          puVar3 = (undefined *)(**(code **)(puVar3 + 8))(piVar1,extraout_r1_02,param_3);
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar3 = (undefined *)(**(code **)(iVar7 + 0x24))();
        }
        return puVar3;
      }
      puVar9 = (undefined *)0x0;
    }
  }
  puVar13 = &UNK_c173620c;
  pcVar6 = param_3;
  piVar2 = (int *)func_0xc10db594(puVar3);
  uVar8 = extraout_r1_02;
  pcVar5 = extraout_r1_03;
code_r0xc1736210:
  *(undefined **)(puVar11 + -4) = puVar13;
  *(undefined1 **)(puVar11 + -8) = puVar12;
  *(int **)(puVar11 + -0x10) = piVar1;
  *(code **)(puVar11 + -0xc) = param_3;
  *(undefined4 *)(puVar11 + -0x18) = uVar8;
  *(undefined **)(puVar11 + -0x14) = puVar9;
  puVar3 = &UNK_c3478b2e;
  if (piVar2 != (int *)0x0) {
    puVar3 = &UNK_c3478b38;
    if ((int *)*piVar2 != (int *)0x0) {
      iVar7 = *(int *)*piVar2;
      puVar13 = &UNK_c3478b42;
      puVar3 = &UNK_c3478b42;
      if (iVar7 == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        pcVar6 = *(code **)(iVar7 + 0x1c);
      }
      if (iVar7 != 0) {
        if (pcVar6 != (code *)0x0) {
          puVar13 = (undefined *)(*pcVar6)();
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar13 = (undefined *)(**(code **)(iVar7 + 0x24))(2,pcVar5,piVar2[1],pcVar5);
        }
        return puVar13;
      }
      uVar8 = 0;
    }
  }
  puVar13 = &UNK_c1736270;
  piVar4 = (int *)func_0xc10db594(puVar3);
  piVar16 = (int *)(puVar11 + -0x20);
  *(undefined **)(puVar11 + -0x1c) = puVar13;
  *piVar16 = (int)(puVar11 + -8);
  *(int **)(puVar11 + -0x28) = piVar2;
  *(code **)(puVar11 + -0x24) = pcVar5;
  if (piVar4 == (int *)0x0) {
    puVar3 = &UNK_c17362fc;
    piVar1 = (int *)func_0xc10db594(&UNK_c3478976);
    puVar15 = puVar11 + -0x30;
    param_3 = extraout_r1_05;
  }
  els

  [... truncated, 11019 chars total ...]

LPA AID table (immext 0xC27EE280): found 14 references
  VA 0xC0F118D8
  VA 0xC0F11908
  VA 0xC0F11910
  VA 0xC0F11B58
  VA 0xC0F11B64
  VA 0xC0F12140
  VA 0xC0F121A0
  VA 0xC0F12220
  VA 0xC0F12238
  VA 0xC0F12B18
  VA 0xC0F12B78
  VA 0xC0F13354
  VA 0xC0F13884
  VA 0xC0F13AC8

Async result (immext 0xC2149D80): found 8 references
  VA 0xC09CAA44
  VA 0xC09CAA8C
  VA 0xC09CAAB0
  VA 0xC09CAB18
  VA 0xC0A153D4
  VA 0xC0A153F0
  VA 0xC0A15404
  VA 0xC0A15424


Done.
