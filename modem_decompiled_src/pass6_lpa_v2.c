pass6: LPA subsystem — init, handlers, AID matching

Opening existing project: /tmp/ghidra_modem_project/modem

======================================================================
[lpa_main_handler] @ 0xC0F1173C (323 bytes)
======================================================================


int lpa_main_handler(undefined4 param_1,undefined4 param_2,undefined4 param_3,undefined4 param_4)

{
  undefined1 uVar1;
  sbyte sVar2;
  uint uVar3;
  undefined1 *puVar4;
  undefined4 *puVar5;
  sbyte *psVar6;
  undefined1 *puVar7;
  undefined4 uVar8;
  code *extraout_r1;
  int iVar9;
  undefined1 *extraout_r6;
  uint uVar10;
  undefined4 unaff_r20;
  undefined4 unaff_r21;
  int iVar11;
  int *piVar12;
  int in_GP;
  sbyte sVar13;
  undefined4 uStack_a8;
  uint uStack_a4;
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
  undefined1 *puStack_38;
  undefined4 uStack_30;
  int iStack_2c;
  
  uVar3 = lpa_entry_2();
  iVar11 = 2;
  iStack_2c = **(int **)(in_GP + 20000);
  uStack_69 = 10;
  uStack_30 = 0x7fffffff;
  lpa_memcpy_thunk(auStack_80,&UNK_c1cd0678);
  lpa_memset_thunk(auStack_68,0);
  if (uVar3 < 2) {
    if (*(longlong *)(&UNK_c27ee268 + uVar3 * 8) == CONCAT44(unaff_r21,unaff_r20)) {
      sVar13 = -1;
    }
    else {
      sVar13 = 0;
    }
    if (sVar13 == 0) {
      log_2arg();
      (*extraout_r1)(0,0,param_3);
      iVar11 = 0;
    }
    else {
      *(sbyte *)((uint)auStack_68 | 3) = (sbyte)uVar3;
      iVar11 = 1;
      pcStack_4c = extraout_r1;
      uStack_48 = param_3;
      puVar4 = (undefined1 *)lpa_slot_lookup(uVar3,&uStack_30);
      if (puVar4 == (undefined1 *)0x0) {
        sVar13 = -1;
      }
      else {
        sVar13 = 0;
      }
      puVar5 = (undefined4 *)puVar4;
      if (sVar13 != 0) {
        puVar5 = &uStack_a8;
      }
      if (puVar4 == (undefined1 *)0x0) {
        *(uint *)((uint)&stack0xffffffc0 | 4) = (uint)auStack_80 | 1;
        puStack_38 = (undefined1 *)0x301;
        lpa_memcpy_thunk(puVar5,auStack_68);
        iVar9 = lpa_search_entry(&uStack_69);
        if (iVar9 == 0) {
          sVar13 = -1;
        }
        else {
          sVar13 = 0;
        }
        puVar4 = extraout_r6;
        if (sVar13 != 0) {
          puVar4 = puStack_38;
        }
        if (iVar9 == 0) {
          uStack_a8 = 0x10;
          uStack_a4 = *(uint *)((uint)&stack0xffffffc0 | 4);
          puStack_a0 = puVar4;
          func_0xc0f11888(_UNK_c27ee260,_UNK_c27ee264,uStack_30,param_4,&UNK_c0f11a20);
          iVar11 = 0;
          iVar9 = lpa_register_handler();
          if (iVar9 == 0) goto LAB_c0f11864;
        }
        lpa_cleanup(uStack_69);
        iVar11 = iVar9;
      }
    }
  }
LAB_c0f11864:
  if (**(int **)(in_GP + 20000) != iStack_2c) {
    func_0xc08f9b60();
    psVar6 = (sbyte *)lpa_search_thunk();
    uVar3 = uStack_a8;
    iVar11 = 1;
    if (psVar6 != (sbyte *)0x0) {
      uVar1 = uStack_a8._1_1_;
      log_3arg(&UNK_c1a626c8,uStack_a8 & 0xff,uStack_a8 >> 8 & 0xff);
      sVar13 = 0;
      do {
        sVar2 = sVar13;
        if ((char)sVar2 < '\n') {
          sVar13 = 0;
        }
        else {
          sVar13 = -1;
        }
        uVar10 = (uint)(char)sVar2;
      } while ((sVar13 == 0) && (sVar13 = sVar2 + 1, *(int *)(&UNK_c27ee290 + uVar10 * 4) != 0));
      if (sVar2 == 10) {
        sVar13 = -1;
      }
      else {
        sVar13 = 0;
      }
      if (sVar13 == 0) {
        iVar11 = 4;
        puVar7 = (undefined1 *)func_0xc0f12bb0(0x24);
        puVar4 = puStack_a0;
        *(undefined1 **)(&UNK_c27ee290 + uVar10 * 4) = puVar7;
        if (puVar7 != (undefined1 *)0x0) {
          piVar12 = (int *)(&UNK_c27ee290 + uVar10 * 4);
          if (puStack_a0 == (undefined1 *)0x0) {
            sVar13 = -1;
          }
          else {
            sVar13 = 0;
          }
          if (sVar13 == 0) {
            uVar10 = uStack_9c;
          }
          if (puStack_a0 != (undefined1 *)0x0) {
            if (uVar10 == 0) {
              sVar13 = -1;
            }
            else {
              sVar13 = 0;
            }
            if (sVar13 == 0) {
              puVar7 = puStack_a0;
            }
            if (uVar10 != 0) {
              uVar8 = func_0xc0f12ba4();
              *(undefined4 *)(*piVar12 + 0xc) = uVar8;
              iVar11 = *(int *)(*piVar12 + 0xc);
              if (iVar11 == 0) {
                sVar13 = -1;
              }
              else {
                sVar13 = 0;
              }
              if (sVar13 == 0) {
                *(undefined1 **)(*piVar12 + 8) = puVar4;
              }
              if (iVar11 == 0) {
                return 4;
              }
              memscpy(*(undefined4 *)(*piVar12 + 0xc),*(undefined4 *)(*piVar12 + 8));
              puVar7 = (undefined1 *)*piVar12;
            }
          }
          *puVar7 = (sbyte)uVar3;
          *(undefined1 *)(*piVar12 + 3) = 0;
          *(undefined1 *)(*piVar12 + 1) = uVar1;
          *(undefined1 *)(*piVar12 + 2) = 0;
          *(undefined1 *)(*piVar12 + 4) = (undefined1)uStack_a4;
          lpa_memcpy_thunk(*piVar12 + 0x10,auStack_98);
          iVar11 = 0;
          *(undefined4 *)(*piVar12 + 0x1c) = uStack_8c;
          iVar9 = *piVar12;
          *psVar6 = sVar2;
          *(undefined4 *)(iVar9 + 0x20) = uStack_88;
        }
      }
      else {
        log_1arg(&UNK_c1a626d0);
      }
    }
  }
  return iVar11;
}



======================================================================
[lpa_isdr_filter_1] @ 0xC0F115E8 (108 bytes)
======================================================================

undefined1 lpa_isdr_filter_1(void)

{
  short sVar1;
  int iVar2;
  undefined4 unaff_r16;
  undefined4 *unaff_r17;
  undefined4 unaff_r20;
  undefined1 unaff_r21;
  undefined4 in_stack_00000000;
  undefined4 in_stack_00000004;
  
  sVar1 = lpa_aid_lookup_1();
  func_0xc0f11734(unaff_r20);
  if ((sVar1 == 0) && (sVar1 = lpa_aid_lookup_2(unaff_r16,&stack0x00000000), sVar1 == 0)) {
    unaff_r21 = 4;
    iVar2 = func_0xc0f11728(in_stack_00000004);
    unaff_r17[1] = iVar2;
    if (iVar2 != 0) {
      unaff_r21 = 0;
      *unaff_r17 = in_stack_00000004;
      memscpy(iVar2,in_stack_00000004,in_stack_00000000,in_stack_00000004);
    }
  }
  lpa_aid_free(unaff_r16);
  return unaff_r21;
}



======================================================================
[lpa_isdr_filter_2] @ 0xC0F116B4 (108 bytes)
======================================================================

undefined1 lpa_isdr_filter_2(undefined4 param_1)

{
  short sVar1;
  int iVar2;
  undefined4 unaff_r16;
  undefined4 *unaff_r17;
  undefined4 unaff_r18;
  undefined1 unaff_r20;
  int unaff_r21;
  undefined4 in_stack_00000000;
  undefined4 in_stack_00000004;
  
  *(undefined4 *)(unaff_r21 + 8) = param_1;
  sVar1 = lpa_aid_lookup_1(unaff_r18,&UNK_c1cd064e,&stack0x00000008);
  func_0xc0f11734();
  if ((sVar1 == 0) && (sVar1 = lpa_aid_lookup_2(unaff_r16,&stack0x00000000), sVar1 == 0)) {
    unaff_r20 = 4;
    iVar2 = func_0xc0f11728(in_stack_00000004);
    unaff_r17[1] = iVar2;
    if (iVar2 != 0) {
      unaff_r20 = 0;
      *unaff_r17 = in_stack_00000004;
      memscpy(iVar2,in_stack_00000004,in_stack_00000000,in_stack_00000004);
    }
  }
  lpa_aid_free(unaff_r16);
  return unaff_r20;
}



======================================================================
FAILED to create function at 0xC0F11758
======================================================================
  FAILED to create function at 0xC0F11758

======================================================================
[lpa_entry_1] @ 0xC0F108B4 (8 bytes)
======================================================================

void lpa_entry_1(void)

{
  return;
}



======================================================================
[lpa_entry_2] @ 0xC0F10514 (8 bytes)
======================================================================

void lpa_entry_2(void)

{
  return;
}



======================================================================
[lpa_register] @ 0xC0F0D384 (32 bytes)
======================================================================

bool lpa_register(undefined4 param_1,undefined4 param_2,undefined4 param_3,uint param_4,
                 undefined1 param_5)

{
  int iVar1;
  
  if (param_4 < 2) {
    iVar1 = param_4 * 0x10;
    *(undefined4 *)(&UNK_c27edebc + iVar1) = param_2;
    *(undefined4 *)(&UNK_c27edec0 + iVar1) = param_3;
    (&UNK_c27edec4)[iVar1] = param_5;
    *(undefined4 *)(&UNK_c27edeb8 + iVar1) = param_1;
  }
  return param_4 >= 2;
}



======================================================================
[lpa_search_entry] @ 0xC0F11890 (300 bytes)
======================================================================

undefined4 lpa_search_entry(void)

{
  sbyte sVar1;
  sbyte *psVar2;
  undefined1 *puVar3;
  int iVar4;
  uint uVar5;
  undefined4 uVar6;
  int *piVar7;
  sbyte sVar8;
  uint in_stack_00000000;
  undefined1 in_stack_00000004;
  undefined1 *in_stack_00000008;
  uint in_stack_0000000c;
  undefined4 in_stack_0000001c;
  undefined4 in_stack_00000020;
  
  psVar2 = (sbyte *)lpa_search_thunk();
  uVar6 = 1;
  if (psVar2 != (sbyte *)0x0) {
    log_3arg(&UNK_c1a626c8,in_stack_00000000 & 0xff,in_stack_00000000 >> 8 & 0xff);
    sVar8 = 0;
    do {
      sVar1 = sVar8;
      if ((char)sVar1 < '\n') {
        sVar8 = 0;
      }
      else {
        sVar8 = -1;
      }
      uVar5 = (uint)(char)sVar1;
    } while ((sVar8 == 0) && (sVar8 = sVar1 + 1, *(int *)(&UNK_c27ee290 + uVar5 * 4) != 0));
    if (sVar1 == 10) {
      sVar8 = -1;
    }
    else {
      sVar8 = 0;
    }
    if (sVar8 == 0) {
      uVar6 = 4;
      puVar3 = (undefined1 *)func_0xc0f12bb0(0x24);
      *(undefined1 **)(&UNK_c27ee290 + uVar5 * 4) = puVar3;
      if (puVar3 != (undefined1 *)0x0) {
        piVar7 = (int *)(&UNK_c27ee290 + uVar5 * 4);
        if (in_stack_00000008 == (undefined1 *)0x0) {
          sVar8 = -1;
        }
        else {
          sVar8 = 0;
        }
        if (sVar8 == 0) {
          uVar5 = in_stack_0000000c;
        }
        if (in_stack_00000008 != (undefined1 *)0x0) {
          if (uVar5 == 0) {
            sVar8 = -1;
          }
          else {
            sVar8 = 0;
          }
          if (sVar8 == 0) {
            puVar3 = in_stack_00000008;
          }
          if (uVar5 != 0) {
            uVar6 = func_0xc0f12ba4();
            *(undefined4 *)(*piVar7 + 0xc) = uVar6;
            iVar4 = *(int *)(*piVar7 + 0xc);
            if (iVar4 == 0) {
              sVar8 = -1;
            }
            else {
              sVar8 = 0;
            }
            if (sVar8 == 0) {
              *(undefined1 **)(*piVar7 + 8) = in_stack_00000008;
            }
            if (iVar4 == 0) {
              return 4;
            }
            memscpy(*(undefined4 *)(*piVar7 + 0xc),*(undefined4 *)(*piVar7 + 8));
            puVar3 = (undefined1 *)*piVar7;
          }
        }
        *puVar3 = (sbyte)in_stack_00000000;
        *(undefined1 *)(*piVar7 + 3) = 0;
        *(undefined1 *)(*piVar7 + 1) = in_stack_00000000._1_1_;
        *(undefined1 *)(*piVar7 + 2) = 0;
        *(undefined1 *)(*piVar7 + 4) = in_stack_00000004;
        lpa_memcpy_thunk(*piVar7 + 0x10,&stack0x00000010);
        uVar6 = 0;
        *(undefined4 *)(*piVar7 + 0x1c) = in_stack_0000001c;
        iVar4 = *piVar7;
        *psVar2 = sVar1;
        *(undefined4 *)(iVar4 + 0x20) = in_stack_00000020;
      }
    }
    else {
      log_1arg(&UNK_c1a626d0);
    }
  }
  return uVar6;
}



======================================================================
[lpa_register_handler] @ 0xC0F12D5C (52 bytes)
======================================================================

undefined4 lpa_register_handler(uint param_1)

{
  undefined4 uVar1;
  sbyte sVar2;
  
  if (param_1 < 0x3c) {
    uVar1 = 0;
    if (param_1 == 0) {
      return 0;
    }
    if (param_1 == 1) {
      sVar2 = -1;
    }
    else {
      sVar2 = 0;
    }
    if (sVar2 != 0) {
      uVar1 = 2;
    }
    if (param_1 == 1) {
      return uVar1;
    }
  }
  else if (param_1 == 0x3c) {
    return 0x12;
  }
  return 1;
}



======================================================================
[lpa_cleanup] @ 0xC0F11B4C (132 bytes)
======================================================================


void lpa_cleanup(uint param_1)

{
  int iVar1;
  int iVar2;
  int iVar3;
  int *piVar4;
  sbyte sVar5;
  
  if ((param_1 < 10) && (*(int *)(&UNK_c27ee290 + param_1 * 4) != 0)) {
    piVar4 = (int *)(&UNK_c27ee290 + param_1 * 4);
    log_2arg(&UNK_c1a626b0);
    iVar1 = *piVar4;
    iVar2 = *(int *)(iVar1 + 8);
    if (iVar2 == 0) {
      sVar5 = -1;
    }
    else {
      sVar5 = 0;
    }
    iVar3 = iVar2;
    if (sVar5 == 0) {
      iVar3 = *(int *)(iVar1 + 0xc);
    }
    if (iVar2 != 0) {
      if (iVar3 == 0) {
        sVar5 = -1;
      }
      else {
        sVar5 = 0;
      }
      if (sVar5 == 0) {
        iVar1 = iVar3;
      }
      if (iVar3 != 0) {
        func_0xc0f12b9c(iVar1);
        *(undefined4 *)(*piVar4 + 0xc) = 0;
        iVar1 = *piVar4;
      }
    }
    lpa_memset_thunk(iVar1,0,0x24);
    if (*piVar4 != 0) {
      func_0xc0f12b9c();
      *piVar4 = 0;
    }
  }
  else {
    log_3arg(&UNK_c1a626a8,param_1,10);
  }
  return;
}




Done.
