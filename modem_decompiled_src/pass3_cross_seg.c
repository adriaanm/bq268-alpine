Pass 3: Cross-segment functions (using full modem.elf)

======================================================================
[session_state_lookup] FUN_c0717d4c @ 0xC0717D4C (384 bytes)
======================================================================

/* WARNING: Removing unreachable block (ram,0xc0717d94) */
/* WARNING: Removing unreachable block (ram,0xc0717d9c) */
/* WARNING: Removing unreachable block (ram,0xc0717da0) */
/* WARNING: Removing unreachable block (ram,0xc0717dd0) */
/* WARNING: Removing unreachable block (ram,0xc0717de0) */
/* WARNING: Removing unreachable block (ram,0xc0717de4) */
/* WARNING: Removing unreachable block (ram,0xc0717df0) */
/* WARNING: Removing unreachable block (ram,0xc0717e14) */
/* WARNING: Removing unreachable block (ram,0xc0717e20) */
/* WARNING: Removing unreachable block (ram,0xc0717e24) */
/* WARNING: Removing unreachable block (ram,0xc0717e30) */
/* WARNING: Removing unreachable block (ram,0xc0717e34) */
/* WARNING: Removing unreachable block (ram,0xc0717e4c) */
/* WARNING: Removing unreachable block (ram,0xc0717e68) */
/* WARNING: Removing unreachable block (ram,0xc0717e70) */
/* WARNING: Removing unreachable block (ram,0xc0717e74) */
/* WARNING: Removing unreachable block (ram,0xc0717e7c) */
/* WARNING: Removing unreachable block (ram,0xc0717e80) */
/* WARNING: Removing unreachable block (ram,0xc0717e84) */
/* WARNING: Removing unreachable block (ram,0xc0717e88) */
/* WARNING: Removing unreachable block (ram,0xc0717ea4) */
/* WARNING: Removing unreachable block (ram,0xc0717eac) */
/* WARNING: Removing unreachable block (ram,0xc0717eb0) */
/* WARNING: Removing unreachable block (ram,0xc0717eb8) */
/* WARNING: Removing unreachable block (ram,0xc0717e94) */
/* WARNING: Removing unreachable block (ram,0xc0717e98) */
/* WARNING: Removing unreachable block (ram,0xc0717ea0) */
/* WARNING: Removing unreachable block (ram,0xc0717ec0) */
/* WARNING: Removing unreachable block (ram,0xc0717ec8) */

undefined1 FUN_c0717d4c(int param_1,uint param_2)

{
  undefined *puVar1;
  int iVar2;
  
  puVar1 = &UNK_c34498c2;
  if (param_2 < 0x13f) {
    iVar2 = *(int *)(param_1 * 4 + -0x3f8cd978) + param_2 * 0x2c;
    puVar1 = &UNK_c34498cc;
    if (iVar2 != 0) {
      return *(undefined1 *)(iVar2 + 2);
    }
  }
  func_0xc0712140(puVar1);
  return 0;
}



======================================================================
[lpa_state_read] FUN_c0717134 @ 0xC0717134 (48 bytes)
======================================================================

undefined4 FUN_c0717134(int param_1)

{
  undefined4 uVar1;
  sbyte sVar2;
  undefined4 uStack_18;
  undefined4 uStack_14;
  undefined1 *puStack_10;
  undefined4 uStack_c;
  
  if (param_1 == 0) {
    sVar2 = -1;
  }
  else {
    sVar2 = 0;
  }
  if (sVar2 != 0) {
    uVar1 = 0xc071714c;
    uStack_14 = func_0xc0712140(&UNK_c3478a48);
    puStack_10 = &stack0xfffffff8;
    uStack_c = uVar1;
    func_0xc071aaf0(&uStack_14,&uStack_18,1);
    return uStack_18;
  }
  return *(undefined4 *)(param_1 + 4);
}



======================================================================
[get_current_task] FUN_c0714400 @ 0xC0714400 (4 bytes)
======================================================================

undefined4 FUN_c0714400(void)

{
  return 0;
}



======================================================================
[session_state_byte] FUN_c0717168 @ 0xC0717168 (12 bytes)
======================================================================

undefined1 FUN_c0717168(int param_1)

{
  return *(undefined1 *)(*(int *)(param_1 * 4 + -0x3f8cd880) + 1);
}



======================================================================
[signal_init] FUN_c0715c10 @ 0xC0715C10 (20 bytes)
======================================================================

void FUN_c0715c10(void)

{
  func_0xc07169e0();
  return;
}



======================================================================
[signal_wait] FUN_c0716820 @ 0xC0716820 (668 bytes)
======================================================================

/* WARNING: Heritage AFTER dead removal. Example location: r1 : 0xc07168e0 */
/* WARNING: Restarted to delay deadcode elimination for space: register */

uint * FUN_c0716820(void)

{
  ulonglong in_r1r0;
  int iVar2;
  ulonglong uVar1;
  undefined *puVar3;
  undefined1 uVar4;
  undefined1 uVar5;
  undefined *puVar6;
  uint *puVar7;
  uint *puVar8;
  uint uVar9;
  ulonglong in_r21r20;
  uint *puVar10;
  sbyte unaff_r24;
  undefined4 uVar11;
  sbyte sVar12;
  uint uStack_48;
  
  puVar8 = (uint *)in_r1r0;
  uVar5 = 0x26;
  puVar3 = &UNK_c343a9bc;
  uVar4 = 0xc0;
  puVar10 = (uint *)(in_r1r0 >> 0x20);
  if (((iRamc0732794 != 0x31415926) || (puVar3 = &UNK_c343a9c6, puVar8 == (uint *)0x0)) ||
     (puVar3 = &UNK_c343a9d0, puVar10 < (uint *)0x10)) {
    iVar2 = iRamc0732794;
    func_0xc0712140(puVar3);
    puVar6 = &UNK_c343aaca;
    if ((puVar8 != (uint *)0x0) && (puVar6 = &UNK_c343aad4, uStack_48 < 2)) {
      puVar8[3] = 0;
      puVar8[2] = 0;
      uVar1 = in_r1r0 & 0xffffffff;
      puVar8[1] = 0;
      *puVar8 = 0;
      *(short *)(puVar8 + 1) = (short)(in_r1r0 >> 0x20);
      *puVar8 = (uStack_48 & 7) << 0xd | (uint)puVar3 & 0xffff1fe7;
      if (iRamc0732794 == 0x31415926) {
        uVar1 = (ulonglong)CONCAT14(*(undefined1 *)(iRamc07327a0 + iRamc07327a8 * 0x10),puVar8);
      }
      puVar10 = (uint *)uVar1;
      *(undefined1 *)((int)puVar10 + 7) = uVar4;
      *(sbyte *)((int)puVar10 + 9) = (sbyte)iVar2;
      *(sbyte *)((int)puVar10 + 6) = (sbyte)(uVar1 >> 0x20);
      *(undefined1 *)(puVar10 + 2) = uVar5;
      *(undefined1 *)((int)puVar10 + 10) = 0;
      return puVar10;
    }
    func_0xc0712140(puVar6);
    if (puVar10 == (uint *)0x0) {
      sVar12 = -1;
    }
    else {
      sVar12 = 0;
    }
    if (sVar12 != 0) {
      uVar11 = 0xc0716a80;
      func_0xc0712140(&UNK_c34077c2);
      puVar10 = (uint *)0x0;
      if (puVar8 != (uint *)0x0) {
        func_0xc0716ac0();
        func_0xc071b440();
                    /* WARNING: Ignoring partial resolution of indirect */
        func_0xc07150f4(&UNK_c2ee0488,puVar8,uVar11,puVar8);
        puVar10 = puVar8;
      }
      return puVar10;
    }
    *puVar10 = 0;
    return puVar10;
  }
  do {
    iVar2 = memw_locked(0xc33f1f00);
    sVar12 = memw_locked_store(0xc33f1f00,iVar2 + 1);
  } while (sVar12 == 0);
  func_0xc07171b0(*puVar8);
                    /* WARNING: Ignoring partial resolution of indirect */
  if ((int)in_r21r20 == 0) {
    sVar12 = -1;
  }
  else {
    sVar12 = 0;
  }
  if (sVar12 == 0) {
    unaff_r24 = 0;
  }
  if ((int)in_r21r20 != 0) {
    if (sVar12 == 0) {
      puVar7 = (uint *)0x0;
    }
    else {
      puVar7 = (uint *)0x6d;
    }
    do {
      uVar9 = (uint)in_r21r20;
      if (*puVar8 == uVar9) {
        sVar12 = -1;
      }
      else {
        sVar12 = 0;
      }
      if (sVar12 == 0) {
        in_r21r20 = in_r21r20 & 0xffffffffffff;
      }
      if (*puVar8 == uVar9) {
        func_0xc07170e0();
        if (puVar8 == (uint *)0x0) {
          func_0xc0718870(4,puVar10,puVar10);
        }
        unaff_r24 = 1;
        in_r21r20 = in_r21r20 & 0xffffffffffff;
        func_0xc0715d00();
        func_0xc0717f50();
        if (puVar8 != (uint *)0x0) {
          puVar7 = (uint *)0x1;
        }
        if (pcRamc0732798 != (code *)0x0) {
          (*pcRamc0732798)((short)puVar8[1],puVar10,puVar8);
        }
      }
      func_0xc0719bb0();
                    /* WARNING: Ignoring partial resolution of indirect */
    } while ((int)in_r21r20 != 0);
    if (unaff_r24 == 0) {
      sVar12 = -1;
    }
    else {
      sVar12 = 0;
    }
    if ((sVar12 == 0) && (puVar7 != (uint *)0x6d)) goto LAB_c07169ac;
  }
  puVar7 = (uint *)0x6d;
  if (*(sbyte *)(iRamc07327a0 + iRamc07327a8 * 0x10) == *(sbyte *)((int)puVar8 + 6)) {
    func_0xc0717f50();
  }
LAB_c07169ac:
  do {
    iVar2 = memw_locked(0xc33f1f00);
    sVar12 = memw_locked_store(0xc33f1f00,iVar2 + -1);
  } while (sVar12 == 0);
  return puVar7;
}



======================================================================
[qmi_dispatch] FUN_c0a07700 @ 0xC0A07700 (2992 bytes)
======================================================================

/* WARNING (jumptable): Heritage AFTER dead removal. Revisit: 0x00000000 */
/* WARNING: Possible PIC construction at 0xc0a077d8: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc0a077e0) */
/* WARNING: Removing unreachable block (ram,0xc0a077e8) */
/* WARNING: Removing unreachable block (ram,0xc0a077ec) */
/* WARNING: Removing unreachable block (ram,0xc0a077f8) */
/* WARNING: Removing unreachable block (ram,0xc0a07800) */
/* WARNING: Removing unreachable block (ram,0xc0a0780c) */
/* WARNING: Heritage AFTER dead removal. Example location: r1 : 0xc0a07760 */
/* WARNING: Removing unreachable block (ram,0xc0a0826c) */
/* WARNING: Removing unreachable block (ram,0xc0a07f14) */
/* WARNING: Removing unreachable block (ram,0xc0a07f18) */
/* WARNING: Removing unreachable block (ram,0xc0a07f20) */
/* WARNING: Removing unreachable block (ram,0xc0a07f30) */
/* WARNING: Removing unreachable block (ram,0xc0a07f3c) */
/* WARNING: Removing unreachable block (ram,0xc0a07f44) */
/* WARNING: Removing unreachable block (ram,0xc0a07f48) */
/* WARNING: Removing unreachable block (ram,0xc0a07f58) */
/* WARNING: Removing unreachable block (ram,0xc0a07f0c) */
/* WARNING: Removing unreachable block (ram,0xc0a07a7c) */
/* WARNING: Removing unreachable block (ram,0xc0a07c6c) */
/* WARNING: Removing unreachable block (ram,0xc0a07a8c) */
/* WARNING: Removing unreachable block (ram,0xc0a07a90) */
/* WARNING: Removing unreachable block (ram,0xc0a07a9c) */
/* WARNING: Removing unreachable block (ram,0xc0a07ab0) */
/* WARNING: Removing unreachable block (ram,0xc0a07abc) */
/* WARNING: Removing unreachable block (ram,0xc0a07ac4) */
/* WARNING: Removing unreachable block (ram,0xc0a07ad4) */
/* WARNING: Removing unreachable block (ram,0xc0a07ae8) */
/* WARNING: Removing unreachable block (ram,0xc0a07af4) */
/* WARNING: Removing unreachable block (ram,0xc0a07b04) */
/* WARNING: Removing unreachable block (ram,0xc0a07b0c) */
/* WARNING: Removing unreachable block (ram,0xc0a07b18) */
/* WARNING: Removing unreachable block (ram,0xc0a07b1c) */
/* WARNING: Removing unreachable block (ram,0xc0a07b28) */
/* WARNING: Removing unreachable block (ram,0xc0a07b3c) */
/* WARNING: Removing unreachable block (ram,0xc0a07b38) */
/* WARNING: Removing unreachable block (ram,0xc0a07b48) */
/* WARNING: Removing unreachable block (ram,0xc0a07b5c) */
/* WARNING: Removing unreachable block (ram,0xc0a07b58) */
/* WARNING: Removing unreachable block (ram,0xc0a07b68) */
/* WARNING: Removing unreachable block (ram,0xc0a07b78) */
/* WARNING: Removing unreachable block (ram,0xc0a07b88) */
/* WARNING: Removing unreachable block (ram,0xc0a07b90) */
/* WARNING: Removing unreachable block (ram,0xc0a07b98) */
/* WARNING: Removing unreachable block (ram,0xc0a07b9c) */
/* WARNING: Removing unreachable block (ram,0xc0a07ba4) */
/* WARNING: Removing unreachable block (ram,0xc0a07be0) */
/* WARNING: Removing unreachable block (ram,0xc0a07be8) */
/* WARNING: Removing unreachable block (ram,0xc0a07bf0) */
/* WARNING: Removing unreachable block (ram,0xc0a07c08) */
/* WARNING: Removing unreachable block (ram,0xc0a07c18) */
/* WARNING: Removing unreachable block (ram,0xc0a07c20) */
/* WARNING: Removing unreachable block (ram,0xc0a07c38) */
/* WARNING: Removing unreachable block (ram,0xc0a07c40) */
/* WARNING: Removing unreachable block (ram,0xc0a07c58) */
/* WARNING: Removing unreachable block (ram,0xc0a07c78) */
/* WARNING: Removing unreachable block (ram,0xc0a07c94) */
/* WARNING: Removing unreachable block (ram,0xc0a07ca0) */
/* WARNING: Removing unreachable block (ram,0xc0a07ca4) */
/* WARNING: Removing unreachable block (ram,0xc0a07cb0) */
/* WARNING: Removing unreachable block (ram,0xc0a07cc0) */
/* WARNING: Removing unreachable block (ram,0xc0a07cf8) */
/* WARNING: Removing unreachable block (ram,0xc0a07d04) */
/* WARNING: Removing unreachable block (ram,0xc0a07d10) */
/* WARNING: Removing unreachable block (ram,0xc0a07d18) */
/* WARNING: Removing unreachable block (ram,0xc0a07d20) */
/* WARNING: Removing unreachable block (ram,0xc0a07d24) */
/* WARNING: Removing unreachable block (ram,0xc0a07d2c) */
/* WARNING: Removing unreachable block (ram,0xc0a07d3c) */
/* WARNING: Removing unreachable block (ram,0xc0a07d40) */
/* WARNING: Removing unreachable block (ram,0xc0a07d48) */
/* WARNING: Removing unreachable block (ram,0xc0a07d4c) */
/* WARNING: Removing unreachable block (ram,0xc0a07d50) */
/* WARNING: Removing unreachable block (ram,0xc0a07d58) */
/* WARNING: Removing unreachable block (ram,0xc0a07d70) */
/* WARNING: Removing unreachable block (ram,0xc0a07d90) */
/* WARNING: Removing unreachable block (ram,0xc0a07d98) */
/* WARNING: Removing unreachable block (ram,0xc0a07da0) */
/* WARNING: Removing unreachable block (ram,0xc0a07da8) */
/* WARNING: Removing unreachable block (ram,0xc0a07dac) */
/* WARNING: Removing unreachable block (ram,0xc0a07db4) */
/* WARNING: Removing unreachable block (ram,0xc0a07de8) */
/* WARNING: Removing unreachable block (ram,0xc0a07e00) */
/* WARNING: Removing unreachable block (ram,0xc0a07e14) */
/* WARNING: Removing unreachable block (ram,0xc0a07e1c) */
/* WARNING: Removing unreachable block (ram,0xc0a07e24) */
/* WARNING: Removing unreachable block (ram,0xc0a07e5c) */
/* WARNING: Removing unreachable block (ram,0xc0a07e50) */
/* WARNING: Removing unreachable block (ram,0xc0a07e64) */
/* WARNING: Removing unreachable block (ram,0xc0a07e6c) */
/* WARNING: Removing unreachable block (ram,0xc0a07e0c) */
/* WARNING: Removing unreachable block (ram,0xc0a07e78) */
/* WARNING: Removing unreachable block (ram,0xc0a07e88) */
/* WARNING: Removing unreachable block (ram,0xc0a07f94) */
/* WARNING: Removing unreachable block (ram,0xc0a07fa4) */
/* WARNING: Removing unreachable block (ram,0xc0a07fac) */
/* WARNING: Removing unreachable block (ram,0xc0a07fb4) */
/* WARNING: Removing unreachable block (ram,0xc0a07fc0) */
/* WARNING: Removing unreachable block (ram,0xc0a07fcc) */
/* WARNING: Removing unreachable block (ram,0xc0a07f88) */
/* WARNING: Removing unreachable block (ram,0xc0a07f64) */
/* WARNING: Removing unreachable block (ram,0xc0a08208) */
/* WARNING: Restarted to delay deadcode elimination for space: register */

void FUN_c0a07700(void)

{
  uint uVar1;
  sbyte sVar2;
  uint uVar3;
  sbyte *psVar4;
  undefined8 in_r1r0;
  ushort *puVar7;
  ulonglong uVar5;
  ulonglong uVar6;
  undefined1 *puVar8;
  uint uVar9;
  uint uVar10;
  int iVar11;
  uint uVar12;
  uint unaff_r20;
  undefined4 *puVar13;
  uint unaff_r22;
  uint unaff_r23;
  uint unaff_r24;
  undefined4 *unaff_r26;
  ushort *unaff_r27;
  int in_GP;
  sbyte sVar14;
  sbyte sVar15;
  uint uVar16;
  uint uStack_148;
  uint uStack_144;
  int iStack_134;
  uint uStack_12c;
  sbyte sStack_128;
  undefined1 uStack_119;
  undefined1 auStack_118 [200];
  
  iVar11 = (int)in_r1r0;
  puVar7 = (ushort *)((ulonglong)in_r1r0 >> 0x20);
  func_0xc0a16da8();
  uVar5 = CONCAT44(&UNK_c3453fca,iVar11);
  uVar12 = *(uint *)(&UNK_c2da5600 + iVar11 * 4);
  if ((uVar12 == 0) || (uVar5 = CONCAT44(&UNK_c3453fd4,iVar11), puVar7 == (ushort *)0x0)) {
LAB_c0a07814:
    func_0xc10db594((int)(uVar5 >> 0x20));
  }
  else {
    if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a07754:
      func_0xc0bde33c(&UNK_c1b689b0,&UNK_c3453fd4,puVar7[1]);
    }
    else {
      if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
          sVar14 = -1;
        }
        else {
          sVar14 = 0;
        }
        if (sVar14 == 0) goto LAB_c0a07754;
      }
    }
    uVar5 = CONCAT44(&UNK_c3453fde,(int)(short)*puVar7);
    if ((puVar7[1] & *puVar7) == 0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    if (sVar14 == 0) goto LAB_c0a07814;
    if (puVar7[1] == 0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    if (sVar14 == 0) {
      func_0xc0a07450();
      uVar5 = (ulonglong)(uint)(

  [... truncated, 17633 chars total ...]


Done.
