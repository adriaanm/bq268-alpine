Pass 2: AID filter chain (using b12 ELF)

======================================================================
[session_or_aid_check] thunk_EXT_FUN_c0717d4c @ 0xC0985C7C (4 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void thunk_EXT_FUN_c0717d4c(void)

{
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[aid_compare] FUN_c09847f8 @ 0xC09847F8 (872 bytes)
======================================================================

/* WARNING: Possible PIC construction at 0xc09848a0: Changing call to branch */
/* WARNING: Removing unreachable block (ram,0xc09848ac) */
/* WARNING: Removing unreachable block (ram,0xc09848b8) */
/* WARNING: Removing unreachable block (ram,0xc09848c0) */
/* WARNING: Heritage AFTER dead removal. Example location: r1 : 0xc0984818 */
/* WARNING: Removing unreachable block (ram,0xc098489c) */
/* WARNING: Removing unreachable block (ram,0xc0984894) */
/* WARNING: Removing unreachable block (ram,0xc09849d8) */
/* WARNING: Restarted to delay deadcode elimination for space: register */

uint FUN_c09847f8(void)

{
  undefined1 uVar1;
  ushort uVar2;
  int iVar3;
  undefined1 uVar4;
  uint uVar5;
  uint uVar6;
  ulonglong in_r1r0;
  ushort *puVar7;
  uint uVar8;
  uint uVar9;
  undefined8 in_r3r2;
  undefined4 uVar10;
  undefined4 uVar11;
  uint unaff_r18;
  ushort *puVar12;
  undefined1 *unaff_r20;
  undefined2 *unaff_r21;
  uint unaff_r22;
  undefined1 *unaff_r25;
  int iVar13;
  sbyte sVar14;
  sbyte sVar15;
  undefined2 auStack_70 [3];
  undefined1 uStack_69;
  
  iVar13 = (int)in_r1r0;
  puVar7 = (ushort *)(in_r1r0 >> 0x20);
  uVar10 = (undefined4)((ulonglong)in_r3r2 >> 0x20);
  uVar9 = 0x13f;
  if (puVar7 < (ushort *)0x13f) {
    func_0xc0986b70();
    if (iVar13 == 1) {
      func_0xc0986ae0(1,0,puVar7);
    }
    return (uint)(iVar13 == 1);
  }
  func_0xc10db594(0xc344994e);
  if ((*(sbyte *)((int)puVar7 + 3) == 1) && (uVar5 = (uint)*puVar7, uVar5 < 0x13f)) {
    in_r1r0 = CONCAT44(puVar7,0xc344996c);
    uVar9 = *(uint *)(iVar13 * 4 + -0x3f8cd978);
    puVar12 = (ushort *)(uVar9 + uVar5 * 0x2c);
    if (puVar12 == (ushort *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    if (sVar14 == 0) {
      unaff_r18 = (uint)(char)puVar12[1];
    }
    if (puVar12 == (ushort *)0x0) goto LAB_c098495c;
    unaff_r20 = (undefined1 *)(uVar5 * 0x2c + uVar9 + 2);
    if (unaff_r18 == 0) {
      *unaff_r20 = 1;
      uVar4 = uRamc1deeaa8;
      iVar3 = (uint)*puVar12 * 8;
      *(sbyte *)(puVar12 + 0xe) = (sbyte)puVar7[2];
      uVar2 = *(ushort *)(iVar3 + -0x3e211556);
      uVar11 = *(undefined4 *)(iVar3 + -0x3e211554);
      *(undefined4 *)(puVar12 + 2) = *(undefined4 *)(puVar7 + 4);
      uVar1 = *(undefined1 *)(iVar3 + -0x3e211557);
      *(sbyte *)(puVar12 + 6) = (sbyte)puVar7[2];
      uVar10 = *(undefined4 *)(puVar7 + 6);
      puVar12[0x14] = 0;
      puVar12[0x13] = 0;
      *(undefined1 *)(puVar12 + 0x12) = 0;
      *(undefined4 *)(puVar12 + 0x10) = uVar11;
      *(undefined1 *)((int)puVar12 + 9) = uVar1;
      puVar12[5] = uVar2;
      *(undefined1 *)(puVar12 + 4) = uVar4;
      *(undefined4 *)(puVar12 + 0xc) = uVar10;
      func_0xc071c710(iVar13);
      if ((uRamc0732bac & 0x2000) == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        func_0xc0bde25c(0xc1b647f8);
      }
      return 0xc344996c;
    }
    in_r1r0 = (ulonglong)CONCAT24(*puVar12,iVar13);
    uVar9 = 1;
    uVar10 = 0;
  }
  else {
LAB_c098495c:
    func_0xc10db594();
  }
  uVar8 = (uint)(in_r1r0 >> 0x20);
  uVar5 = (uint)in_r1r0;
  uVar11 = 0xc34499e4;
  if (uVar8 < 0x13f) {
    uVar11 = 0xc34499ee;
    iVar13 = *(int *)(uVar5 * 4 + -0x3f8cd978);
    unaff_r20 = (undefined1 *)(iVar13 + uVar8 * 0x2c);
    if (unaff_r20 == (undefined1 *)0x0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    if (sVar14 == 0) {
      unaff_r21 = auStack_70;
    }
    if (unaff_r20 == (undefined1 *)0x0) goto LAB_c0984b28;
    auStack_70[0] = (undefined2)(in_r1r0 >> 0x20);
    unaff_r21[2] = 0xffff;
    *(sbyte *)(unaff_r21 + 3) = (sbyte)uVar10;
    func_0xc0987578();
    *(sbyte *)((int)unaff_r21 + 7) = (sbyte)uVar9;
    if ((uVar9 == 2) && (func_0xc071bb78(uVar5), uVar5 == 2)) {
      func_0xc098ab10(2);
      in_r1r0 = CONCAT71((int7)(in_r1r0 >> 8),3);
      uStack_69 = 3;
    }
    uVar11 = *(undefined4 *)(unaff_r20 + 0x18);
    sVar14 = unaff_r20[2];
    func_0xc0984c60();
    if (*(int *)(unaff_r20 + 4) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    unaff_r22 = 1;
    if (sVar15 == 0) {
      unaff_r22 = uVar8 * 0x2c;
    }
    uVar6 = (uint)in_r1r0;
    if (*(int *)(unaff_r20 + 4) != 0) {
      func_0xc098764c(uVar6);
      func_0xc0987768();
      (**(code **)(unaff_r22 + iVar13 + 4))(uVar11);
      func_0xc0987818();
      unaff_r22 = uVar6;
    }
    unaff_r25 = (undefined1 *)(uVar8 * 0x2c + iVar13 + 2);
    if ((uVar8 == 0x70) || (uVar8 == 0x137)) {
      if ((uRamc0732bac & 0x2004) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        func_0xc0bde450();
      }
    }
    func_0xc071bb88(uVar5);
    if ((uVar6 == 1) && (unaff_r22 == 1)) {
      func_0xc0989c94(1);
      func_0xc0989c10(uVar5);
    }
    if ((unaff_r22 - 1 & 0xff) < 2) {
      sVar15 = 0;
    }
    else {
      sVar15 = -1;
    }
    if ((sVar15 != 0) && (uVar11 = 0xc34499f8, unaff_r22 != 3)) goto LAB_c0984b28;
    if (unaff_r22 == 2) {
      sVar15 = -1;
      uVar11 = 0xc3449a02;
      if (uVar8 != 0x43) goto LAB_c0984b28;
    }
    else {
      sVar15 = 0;
    }
    if ((sVar14 == 2) && (sVar15 == 0)) {
      func_0xc0986cb0(uVar5,(int)(in_r1r0 >> 0x20),uVar8);
    }
    if (unaff_r22 != 3) goto LAB_c0984b38;
    if ((uVar6 & 0xff) < 2) {
      sVar14 = 0;
    }
    else {
      sVar14 = -1;
    }
    if (((sVar14 != 0) || (7 < uVar9)) || ((1 << uVar9 & 0x8dU) == 0)) {
      uVar11 = 0xc3449a0c;
      if ((uRamc0732bac & 0x2004) == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) {
        func_0xc0bde450();
      }
      goto LAB_c0984b28;
    }
  }
  else {
LAB_c0984b28:
    func_0xc10db594(uVar11);
  }
  func_0xc0986bc8();
LAB_c0984b38:
                    /* WARNING: Ignoring partial resolution of indirect */
  uVar1 = unaff_r20[8];
  *unaff_r25 = (sbyte)unaff_r22;
  func_0xc071c710(uVar5,uVar8,uVar1,uVar10,unaff_r22);
  return uVar5;
}



======================================================================
[isdr_check_1] FUN_c0999610 @ 0xC0999610 (20 bytes)
======================================================================

bool FUN_c0999610(void)

{
  int iVar1;
  
  iVar1 = func_0xc0717134(0xc21499b0);
  return iVar1 == 0;
}



======================================================================
[isdr_check_2] FUN_c0999630 @ 0xC0999630 (20 bytes)
======================================================================

bool FUN_c0999630(void)

{
  int iVar1;
  
  iVar1 = func_0xc0717134(0xc21499b0);
  return iVar1 == 8;
}



======================================================================
[lpa_memcpy_thunk] thunk_EXT_FUN_c070df10 @ 0xC0F1051C (8 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void thunk_EXT_FUN_c070df10(void)

{
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_memset_thunk] thunk_EXT_FUN_c070e4e0 @ 0xC0F11880 (8 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void thunk_EXT_FUN_c070e4e0(void)

{
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_search_thunk] thunk_EXT_FUN_c070dd00 @ 0xC0F119B8 (8 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void thunk_EXT_FUN_c070dd00(void)

{
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_slot_lookup] FUN_c0f12d14 @ 0xC0F12D14 (36 bytes)
======================================================================

undefined4 FUN_c0f12d14(int param_1,undefined4 *param_2)

{
  undefined4 uVar1;
  sbyte sVar2;
  
  uVar1 = 1;
  if (param_2 != (undefined4 *)0x0) {
    if (param_1 == 1) {
      sVar2 = -1;
    }
    else {
      sVar2 = 0;
    }
    if (sVar2 != 0) {
      *param_2 = 2;
    }
    if (param_1 != 1) {
      if (param_1 == 0) {
        sVar2 = -1;
      }
      else {
        sVar2 = 0;
      }
      if (sVar2 != 0) {
        *param_2 = 1;
      }
      if (param_1 != 0) {
        return 1;
      }
    }
    uVar1 = 0;
  }
  return uVar1;
}



======================================================================
[aid_match_handler] FUN_c098acc0 @ 0xC098ACC0 (96 bytes)
======================================================================

/* WARNING: Restarted to delay deadcode elimination for space: register */

void FUN_c098acc0(int param_1,uint param_2)

{
  int iVar1;
  undefined1 extraout_r1;
  uint uVar2;
  sbyte sVar3;
  
  if (param_2 < 2) {
    sVar3 = -1;
  }
  else {
    sVar3 = 0;
  }
  uVar2 = param_2;
  if (sVar3 != 0) {
    uVar2 = (uint)uRamc0732bac;
  }
  if (param_2 < 2) {
    if ((uVar2 & 0x2002) == 0) {
      sVar3 = -1;
    }
    else {
      sVar3 = 0;
    }
    if (sVar3 == 0) {
      func_0xc0bde2c8();
    }
    *(sbyte *)(*(int *)(param_1 * 4 + -0x3f8cd880) + 1) = (sbyte)param_2;
    return;
  }
  iVar1 = func_0xc10db594(0xc344a4fc);
  *(undefined1 *)(*(int *)(iVar1 * 4 + -0x3f8cd880) + 2) = extraout_r1;
  return;
}



======================================================================
[lpa_aid_lookup_1] FUN_c14b4540 @ 0xC14B4540 (280 bytes)
======================================================================

/* WARNING: Control flow encountered bad instruction data */

void FUN_c14b4540(undefined4 param_1,undefined4 param_2,char *param_3)

{
  bool bVar1;
  uint uVar2;
  uint uVar3;
  uint uVar4;
  uint uVar5;
  uint *extraout_r1;
  uint *puVar6;
  char *pcVar7;
  undefined4 uVar8;
  char *pcVar9;
  uint unaff_r20;
  int in_GP;
  sbyte sVar10;
  undefined1 auStack_78 [36];
  undefined1 auStack_54 [36];
  uint auStack_30 [2];
  char *pcStack_28;
  
  uVar2 = thunk_EXT_FUN_c070dd58();
  bVar1 = uVar2 == 0;
  auStack_30[1] = 0x10;
  puVar6 = extraout_r1;
  if (!bVar1) {
    puVar6 = auStack_30;
  }
  pcStack_28 = (char *)0x0;
  auStack_30[0] = 0;
  if (!bVar1) {
    uVar3 = func_0xc14b40bc(extraout_r1,puVar6);
    if ((uVar3 & 1) == 0) {
      sVar10 = -1;
    }
    else {
      sVar10 = 0;
    }
    uVar4 = uVar3;
    if (sVar10 != 0) {
      uVar4 = (uint)*param_3;
    }
    if ((uVar3 & 1) != 0) {
      if (uVar4 < 6) {
        sVar10 = 0;
      }
      else {
        sVar10 = -1;
      }
      if (sVar10 == 0) {
        unaff_r20 = auStack_30[0];
      }
      if (uVar4 < 6) {
        if (unaff_r20 == 0) {
          if (bVar1) goto code_r0xc070ddf0;
        }
        else {
          uVar3 = 0;
          pcVar9 = pcStack_28;
          do {
            uVar4 = func_0xc14b46ac();
            if (uVar4 == 0) {
              sVar10 = -1;
            }
            else {
              sVar10 = 0;
            }
            uVar5 = uVar4;
            if (sVar10 != 0) {
              uVar5 = (uint)*pcVar9;
            }
            if (uVar4 == 0) {
              if (uVar5 == 0) {
                sVar10 = -1;
              }
              else {
                sVar10 = 0;
              }
              pcVar7 = (char *)0x0;
              if (sVar10 == 0) {
                pcVar7 = pcVar9 + 8;
              }
              if (uVar5 == 0) {
                uVar8 = *(undefined4 *)(pcVar9 + 4);
                func_0xc14b51dc(auStack_54,0);
                func_0xc14b58e0(uVar2,uVar8,auStack_54);
                func_0xc14b5208(auStack_54);
                uVar4 = func_0xc14b5f88(uVar2,*(undefined4 *)(pcVar9 + 4));
              }
              else {
                func_0xc14b51dc(auStack_78,0);
                func_0xc14b5864(uVar2,pcVar7,auStack_78);
                func_0xc14b5208(auStack_78);
                uVar4 = func_0xc14b5f8c();
              }
              if (uVar4 == 0) goto code_r0xc070ddf0;
            }
            pcVar9 = pcVar9 + 0xc;
            uVar3 = uVar3 + 1;
            uVar2 = uVar4;
          } while (uVar3 < unaff_r20);
        }
        if (*param_3 < 6) {
                    /* WARNING: Could not recover jumptable at 0xc14b4644. Too many branches */
                    /* WARNING: Treating indirect jump as call */
          (**(code **)(**(int **)(in_GP + 0xb1d8) + (uint)*param_3 * 4))();
          return;
        }
      }
    }
  }
code_r0xc070ddf0:
  func_0xc14b4448(auStack_30);
                    /* WARNING: Bad instruction - Truncating control flow here */
  halt_baddata();
}



======================================================================
[lpa_aid_lookup_2] FUN_c14b408c @ 0xC14B408C (48 bytes)
======================================================================

short FUN_c14b408c(int param_1,int param_2)

{
  uint uVar1;
  short sVar2;
  sbyte sVar3;
  
  sVar2 = -1;
  if (param_1 != 0) {
    if (param_2 == 0) {
      sVar3 = -1;
    }
    else {
      sVar3 = 0;
    }
    sVar2 = -1;
    if (sVar3 == 0) {
      sVar2 = (short)param_2 + 4;
    }
    if (param_2 != 0) {
      uVar1 = func_0xc14b50d0();
      if ((uVar1 & 1) == 0) {
        sVar3 = 0;
      }
      else {
        sVar3 = -1;
      }
      sVar2 = -4;
      if (sVar3 != 0) {
        sVar2 = 0;
      }
    }
  }
  return sVar2;
}




Done.
