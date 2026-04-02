pass4: MMGSDI dispatch chain — async callback, state machine

Opening existing project: /tmp/ghidra_modem_project/modem

======================================================================
[mmgsdi_async_callback] @ 0xC09CAA78 (288 bytes)
======================================================================


undefined4 mmgsdi_async_callback(int param_1,int param_2)

{
  sbyte sVar1;
  undefined *puVar2;
  undefined4 uVar3;
  int iVar4;
  undefined *puVar5;
  undefined *puVar6;
  int in_GP;
  
  if (param_2 != 0) {
    mmgsdi_session_lookup(param_1);
    mmgsdi_dispatch_thunk();
    sVar1 = mmgsdi_state_machine_thunk(0xc2149db0,param_1,0);
    if (sVar1 == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    puVar6 = &UNK_c344f2cc;
    if (sVar1 == 0) goto LAB_c09cab74;
    *(undefined1 *)(*(int *)(&UNK_c2da5218 + param_1 * 4) + 0x194) = 0;
    *(undefined1 *)(*(int *)(&UNK_c2da5218 + param_1 * 4) + 0x19c) = 0;
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
    log_1arg(&UNK_c1b669b0);
    goto LAB_c09cab5c;
  }
  sVar1 = mmgsdi_async_alt_thunk();
  if (sVar1 == 0) {
    sVar1 = -1;
  }
  else {
    sVar1 = 0;
  }
  puVar6 = &UNK_c344f2d6;
  if (sVar1 == 0) {
LAB_c09cab74:
    iVar4 = msg_send_3(puVar6);
    puVar6 = &UNK_c1df1a2a;
    iVar4 = *(int *)(&UNK_c2da5218 + iVar4 * 4);
    if (iVar4 == 0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    if (sVar1 == 0) {
      puVar6 = (undefined *)0x2f;
    }
    if (iVar4 != 0) {
      puVar2 = &UNK_c3444ff2;
      puVar5 = *(undefined **)(iVar4 + -0x18);
      if (puVar5 == puVar6) {
        puVar2 = &UNK_c3444ffc;
        puVar5 = *(undefined **)(iVar4 + -8);
        if (puVar5 == (undefined *)0x0) {
          puVar2 = &UNK_c3445006;
          puVar5 = *(undefined **)(iVar4 + -4);
          if (puVar5 == (undefined *)0x1234567) {
            func_0xc0920810();
            uVar3 = **(undefined4 **)(in_GP + 0xd4f0);
            *(undefined4 *)(iVar4 + -4) = uVar3;
            *(undefined4 *)(iVar4 + -0x18) = uVar3;
            uVar3 = func_0xc071719c();
            return uVar3;
          }
        }
      }
      msg_send_3(puVar2,puVar5,puVar6,0x3a4);
    }
    uVar3 = log_2arg();
    return uVar3;
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
  log_1arg(&UNK_c1b669b8);
LAB_c09cab5c:
  **(undefined1 **)(&UNK_c2da5218 + param_1 * 4) = 0;
  return 1;
}



======================================================================
[mmgsdi_session_lookup] @ 0xC0A23140 (12 bytes)
======================================================================

undefined4 mmgsdi_session_lookup(int param_1)

{
  return *(undefined4 *)(&UNK_c2da5648 + param_1 * 4);
}



======================================================================
[mmgsdi_dispatch_store_handler] @ 0xC1736674 (28 bytes)
======================================================================


int mmgsdi_dispatch_store_handler(int param_1,undefined4 param_2)

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
  psVar3 = (sbyte *)msg_send_3(&UNK_c3478b10);
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
    if (sVar8 != 0) goto LAB_c1736710;
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
LAB_c1736710:
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
    if (sVar8 != 0) goto LAB_c173674c;
    uVar6 = (uint)(char)sVar7;
    sVar7 = sVar7 + 1;
  } while (*(short *)(psVar3 + 2) != *(short *)(&UNK_c1f8b4fc + uVar6 * 8));
  uStack_38 = *(undefined4 *)(&UNK_c1f8b4f8 + uVar6 * 8);
LAB_c173674c:
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
[mmgsdi_dispatch_lookup] @ 0xC1736690 (232 bytes)
======================================================================


undefined4 mmgsdi_dispatch_lookup(sbyte *param_1,int param_2)

{
  sbyte *psVar1;
  int *piVar2;
  undefined4 uVar3;
  int *piVar4;
  uint uVar5;
  int in_GP;
  sbyte sVar6;
  sbyte sVar7;
  int aiStack_38 [2];
  undefined4 uStack_30;
  undefined4 uStack_2c;
  undefined1 *puStack_28;
  undefined1 auStack_20 [12];
  int iStack_14;
  
  if (param_2 == 0) {
    sVar6 = -1;
  }
  else {
    sVar6 = 0;
  }
  iStack_14 = **(int **)(in_GP + 20000);
  if ((sVar6 != 0) || (param_1 == (sbyte *)0x0)) {
    while( true ) {
      uVar3 = 1;
      func_0xc13e477c(&UNK_c1bf43a4);
code_r0xc17367c0:
      if (**(int **)(in_GP + 20000) == iStack_14) break;
      func_0xc1801040();
    }
    return uVar3;
  }
  piVar4 = (int *)&UNK_c1f8b648;
  do {
    if (*piVar4 == 0) break;
    piVar2 = piVar4 + 1;
    if ((sbyte)*piVar2 == *param_1) {
      sVar6 = -1;
    }
    else {
      sVar6 = 0;
    }
    if (sVar6 != 0) {
      aiStack_38[0] = *piVar4;
    }
    piVar4 = piVar4 + 2;
  } while ((sbyte)*piVar2 != *param_1);
  piVar4 = (int *)&UNK_c1f8b588;
  *(undefined4 *)((uint)aiStack_38 | 4) = 0;
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
    psVar1 = (sbyte *)((int)piVar4 + uVar5 * 8 + 4);
    if (param_1[1] == *psVar1) {
      sVar7 = -1;
    }
    else {
      sVar7 = 0;
    }
    if (sVar7 != 0) {
      piVar4 = aiStack_38;
    }
    sVar6 = sVar6 + 1;
  } while (param_1[1] != *psVar1);
  *(undefined4 *)((uint)piVar4 | 4) = *(undefined4 *)(&UNK_c1f8b588 + uVar5 * 8);
LAB_c1736710:
  if (*param_1 == 5) {
    uStack_30 = *(undefined4 *)(param_1 + 4);
    uStack_2c = *(undefined4 *)(param_1 + 8);
    puStack_28 = *(undefined1 **)(param_1 + 0xc);
    uVar3 = func_0xc1736804(aiStack_38);
    goto code_r0xc17367c0;
  }
  uStack_30 = 0;
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
  } while (*(short *)(param_1 + 2) != *(short *)(&UNK_c1f8b4fc + uVar5 * 8));
  uStack_30 = *(undefined4 *)(&UNK_c1f8b4f8 + uVar5 * 8);
LAB_c173674c:
  sVar6 = param_1[1] & 0xf0;
  uStack_2c = uStack_30;
  if (sVar6 == -0x70) {
    uStack_30 = *(undefined4 *)(param_1 + 4);
  }
  else if (sVar6 == 0x20) {
    uStack_30 = *(undefined4 *)(param_1 + 4);
  }
  else {
    if (param_1[1] != 0x41) {
      uStack_30 = 0;
    }
    uStack_2c = 0;
  }
  puStack_28 = (undefined1 *)0x0;
  if (((*param_1 == 3) && (sVar6 == 0x20)) && (*(int *)(param_1 + 8) != 0)) {
    puStack_28 = auStack_20;
  }
  uVar3 = func_0xc1736804(aiStack_38);
  goto code_r0xc17367c0;
}



======================================================================
[mmgsdi_state_machine] @ 0xC1735ED4 (148 bytes)
======================================================================


undefined * mmgsdi_state_machine(int *param_1,undefined4 param_2,code *param_3)

{
  int *piVar1;
  undefined *puVar2;
  undefined *puVar3;
  int *piVar4;
  undefined4 extraout_r1;
  int *piVar5;
  undefined4 extraout_r1_00;
  undefined4 extraout_r1_01;
  undefined4 extraout_r1_02;
  undefined4 extraout_r1_03;
  code *pcVar6;
  int iVar7;
  sbyte unaff_r20;
  int iVar8;
  sbyte sVar9;
  sbyte sVar10;
  undefined4 uVar11;
  
  if (param_1 != (int *)0x0) {
    piVar1 = (int *)func_0xc1735f64();
    if (piVar1 == (int *)0x0) {
      sVar9 = -1;
    }
    else {
      sVar9 = 0;
    }
    piVar5 = piVar1;
    if (sVar9 != 0) {
      piVar5 = (int *)*param_1;
    }
    if (piVar1 == (int *)0x0) {
      if (*(code **)(*piVar5 + 0x20) == (code *)0x0) {
        sVar9 = -2;
        err_fatal();
      }
      else {
        sVar9 = -2;
        (**(code **)(*piVar5 + 0x20))();
      }
    }
    else {
      sVar9 = mmgsdi_generic_handler();
    }
    return (undefined *)(int)sVar9;
  }
  piVar1 = (int *)msg_send_3(&UNK_c347894e);
  puVar2 = &UNK_c3478958;
  if (piVar1 != (int *)0x0) {
    puVar2 = &UNK_c3478962;
    if (((int *)*piVar1 != (int *)0x0) && (puVar2 = &UNK_c347896c, *(int *)*piVar1 != 0)) {
      sVar9 = mmgsdi_handler_init(piVar1);
      if (sVar9 == 0) {
        sVar9 = -1;
      }
      else {
        sVar9 = 0;
      }
      if (sVar9 == 0) {
        pcVar6 = *(code **)(*(int *)*piVar1 + 0x20);
        if (pcVar6 == (code *)0x0) {
          sVar9 = -1;
        }
        else {
          sVar9 = 0;
        }
        if (sVar9 == 0) {
          unaff_r20 = -1;
        }
        if (pcVar6 == (code *)0x0) {
          unaff_r20 = -1;
          err_fatal(&UNK_c1bf42e4);
        }
        else {
          (*pcVar6)();
        }
code_r0xc1736104:
        return (undefined *)(int)unaff_r20;
      }
      if (piVar1[1] != -2) {
        unaff_r20 = 0;
        mmgsdi_handler_cleanup(piVar1);
        goto code_r0xc1736104;
      }
      piVar5 = (int *)*piVar1;
      puVar2 = &UNK_c3478b88;
      piVar1[3] = 0;
      iVar7 = *piVar5;
      piVar1[2] = -0x81;
      if (piVar5 != (int *)0x0) {
        iVar8 = *piVar5;
        puVar2 = &UNK_c3478b92;
        if (iVar8 == 0) {
          sVar9 = -1;
        }
        else {
          sVar9 = 0;
        }
        if (sVar9 == 0) {
          param_3 = *(code **)(iVar8 + 0x18);
        }
        if (iVar8 != 0) {
          if (param_3 != (code *)0x0) {
            (*param_3)();
          }
          if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
            (**(code **)(iVar8 + 0x24))(0,extraout_r1,piVar1[1],extraout_r1);
          }
          iVar8 = *(int *)(iVar7 + 0x28);
          piVar1[1] = iVar8;
          mmgsdi_handler_continue(piVar1,extraout_r1,extraout_r1,iVar8);
          unaff_r20 = 0;
          iVar8 = piVar1[1];
          iVar7 = *(int *)(*(int *)(iVar7 + 8) + iVar8 * 0x10 + 0xc);
          if (iVar7 == 0) {
            sVar9 = -1;
          }
          else {
            sVar9 = 0;
          }
          if (sVar9 == 0) {
            iVar8 = *piVar1;
          }
          if (iVar7 != 0) {
            sVar9 = mmgsdi_generic_handler(iVar7 + *(int *)(iVar8 + 0xc) * 0x1c);
            if (sVar9 == 0) {
              sVar10 = -1;
            }
            else {
              sVar10 = 0;
            }
            if (sVar10 == 0) {
              mmgsdi_handler_notify();
              piVar1[1] = -0x82;
              mmgsdi_handler_complete();
              pcVar6 = *(code **)(*(int *)*piVar1 + 0x20);
              if (pcVar6 == (code *)0x0) {
                sVar10 = -1;
              }
              else {
                sVar10 = 0;
              }
              unaff_r20 = 0;
              if (sVar10 != 0) {
                unaff_r20 = sVar9;
              }
              if (pcVar6 == (code *)0x0) {
                err_fatal(&UNK_c1bf42f4);
              }
              else {
                (*pcVar6)();
                unaff_r20 = sVar9;
              }
            }
          }
          func_0xc1736128(piVar1);
          goto code_r0xc1736104;
        }
      }
    }
  }
  piVar1 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b6a;
  if (piVar1 != (int *)0x0) {
    puVar2 = &UNK_c3478b74;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar7 = *(int *)*piVar1;
      puVar2 = &UNK_c3478b7e;
      if (iVar7 != 0) {
        puVar2 = (undefined *)(*(int *)(iVar7 + 8) + piVar1[1] * 0x10);
        if (*(code **)(puVar2 + 4) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(puVar2 + 4))(piVar1,extraout_r1_00,param_3);
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(iVar7 + 0x24))();
        }
        return puVar2;
      }
    }
  }
  piVar1 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b4c;
  if (piVar1 != (int *)0x0) {
    puVar2 = &UNK_c3478b56;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar7 = *(int *)*piVar1;
      puVar2 = &UNK_c3478b60;
      if (iVar7 != 0) {
        puVar2 = (undefined *)(*(int *)(iVar7 + 8) + piVar1[1] * 0x10);
        if (*(code **)(puVar2 + 8) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(puVar2 + 8))(piVar1,extraout_r1_01,param_3);
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(iVar7 + 0x24))();
        }
        return puVar2;
      }
    }
  }
  piVar1 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b2e;
  uVar11 = extraout_r1_01;
  if (piVar1 != (int *)0x0) {
    puVar2 = &UNK_c3478b38;
    if ((int *)*piVar1 != (int *)0x0) {
      iVar7 = *(int *)*piVar1;
      puVar3 = &UNK_c3478b42;
      puVar2 = &UNK_c3478b42;
      if (iVar7 == 0) {
        sVar9 = -1;
      }
      else {
        sVar9 = 0;
      }
      if (sVar9 == 0) {
        param_3 = *(code **)(iVar7 + 0x1c);
      }
      if (iVar7 != 0) {
        if (param_3 != (code *)0x0) {
          puVar3 = (undefined *)(*param_3)();
        }
        if (*(code **)(iVar7 + 0x24) != (code *)0x0) {
          puVar3 = (undefined *)
                   (**(code **)(iVar7 + 0x24))(2,extraout_r1_02,piVar1[1],extraout_r1_02);
        }
        return puVar3;
      }
      uVar11 = 0;
    }
  }
  sVar9 = (sbyte)uVar11;
  piVar1 = (int *)msg_send_3(puVar2);
  if (piVar1 != (int *)0x0) {
    piVar5 = (int *)func_0xc1735f64(piVar1);
    if (piVar5 == (int *)0x0) {
      sVar9 = -1;
    }
    else {
      sVar9 = 0;
    }
    piVar4 = piVar5;
    if (sVar9 != 0) {
      piVar4 = (int *)*piVar1;
    }
    if (piVar5 == (int *)0x0) {
      if (*(code **)(*piVar4 + 0x20) == (code *)0x0) {
        sVar9 = -2;
        err_fatal();
      }
      else {
        sVar9 = -2;
        (**(code **)(*piVar4 + 0x20))();
      }
    }
    else {
      sVar9 = mmgsdi_alt_dispatch();
    }
    return (undefined *)(int)sVar9;
  }
  piVar1 = (int *)msg_send_3(&UNK_c3478976);
  puVar2 = &UNK_c3478980;
  if (piVar1 == (int *)0x0) {
LAB_c1736444:
    iVar7 = msg_send_3(puVar2);
    if (5 < iVar7 + 5U) {
      return &UNK_c1f8b49f;
    }
    return *(undefined **)(&UNK_c1f8b4e0 + (iVar7 + 5U) * 4);
  }
  puVar2 = &UNK_c347898a;
  if (((int *)*piVar1 == (int *)0x0) || (puVar2 = &UNK_c3478994, *(int *)*piVar1 == 0))
  goto LAB_c1736444;
  sVar10 = func_0xc173644c(piVar1);
  if (sVar10 == 0) {
    sVar10 = -1;
  }
  else {
    sVar10 = 0;
  }
  if (sVar10 == 0) {
    pcVar6 = *(code **)(*(int *)*piVar1 + 0x20);
    if (pcVar6 == (code *)0x0) {
      sVar10 = -1;
    }
    else {
      sVar10 = 0;
    }
    if (sVar10 == 0) {
      sVar9 = -1;
    }
    if (pcVar6 == (code *)0x0) {
      sVar9 = -1;
      err_fatal(&UNK_c1bf4314);
    }
    else {
      (*pcVar6)();
    }
    goto LAB_c1736438;
  }
  if (piVar1[1] == -2) {
    sVar9 = 0;
    func_0xc1736454(piVar1);
    goto LAB_c1736438;
  }
  piVar5 = (int *)*piVar1;
  iVar7 = *(int *)(*(int *)(*piVar5 + 8) + piVar1[1] * 0x10 + 0xc);
  if (iVar7 == 0) {
    sVar9 = -1;
  }
  else {
    sVar9 = 0;
  }
  if (sVar9 == 0) {
    piVar5 = (int *)piVar5[3];
  }
  if (iVar7 == 0) {
LAB_c17363d8:
    mmgsdi_handler_notify(piVar1,extraout_r1_03,extraout_r1_03);
    sVar9 = 0;
    piVar1[1] = -0x82;
    mmgsdi_handler_complete();
  }
  else {
    sVar9 = mmgsdi_alt_dispatch(iVar7 + (int)piVar5 * 0x1c);
    if (sVar9 == 0) {
      sVar10 = -1;
    }
    else {
      sVar10 = 0;
    }
    if (sVar10 != 0) goto LAB_c17363d8;
    if (*(code **)(*(int *)*piVar1 + 0x20) == (code *)0x0) {
      err_fatal(&UNK_c1bf4324);
    }
    else {
      (**(code **)(*(int *)*piVar1 + 0x20))();
    }
  }
  func_0xc173645c(piVar1);
LAB_c1736438:
  return (undefined *)(int)sVar9;
}



======================================================================
[mmgsdi_generic_handler] @ 0xC1735F70 (104 bytes)
======================================================================


undefined * mmgsdi_generic_handler(code *param_1)

{
  sbyte sVar1;
  undefined *puVar2;
  int *piVar3;
  undefined *puVar4;
  int *piVar5;
  undefined8 in_r1r0;
  int *piVar6;
  undefined4 extraout_r1;
  undefined4 extraout_r1_00;
  undefined4 extraout_r1_01;
  undefined4 extraout_r1_02;
  code *pcVar7;
  int iVar8;
  sbyte unaff_r20;
  int iVar9;
  sbyte sVar10;
  undefined4 uVar11;
  
  uVar11 = (undefined4)((ulonglong)in_r1r0 >> 0x20);
  piVar3 = (int *)in_r1r0;
  puVar2 = &UNK_c3478958;
  if (piVar3 != (int *)0x0) {
    puVar2 = &UNK_c3478962;
    if (((int *)*piVar3 != (int *)0x0) && (puVar2 = &UNK_c347896c, *(int *)*piVar3 != 0)) {
      sVar1 = mmgsdi_handler_init(piVar3);
      if (sVar1 == 0) {
        sVar1 = -1;
      }
      else {
        sVar1 = 0;
      }
      if (sVar1 == 0) {
        pcVar7 = *(code **)(*(int *)*piVar3 + 0x20);
        if (pcVar7 == (code *)0x0) {
          sVar1 = -1;
        }
        else {
          sVar1 = 0;
        }
        if (sVar1 == 0) {
          unaff_r20 = -1;
        }
        if (pcVar7 == (code *)0x0) {
          unaff_r20 = -1;
          err_fatal(&UNK_c1bf42e4);
        }
        else {
          (*pcVar7)();
        }
code_r0xc1736104:
        return (undefined *)(int)unaff_r20;
      }
      if (piVar3[1] != -2) {
        unaff_r20 = 0;
        mmgsdi_handler_cleanup(piVar3);
        goto code_r0xc1736104;
      }
      piVar6 = (int *)*piVar3;
      puVar2 = &UNK_c3478b88;
      piVar3[3] = 0;
      iVar8 = *piVar6;
      piVar3[2] = -0x81;
      if (piVar6 != (int *)0x0) {
        iVar9 = *piVar6;
        puVar2 = &UNK_c3478b92;
        if (iVar9 == 0) {
          sVar1 = -1;
        }
        else {
          sVar1 = 0;
        }
        if (sVar1 == 0) {
          param_1 = *(code **)(iVar9 + 0x18);
        }
        if (iVar9 != 0) {
          if (param_1 != (code *)0x0) {
            (*param_1)();
          }
          if (*(code **)(iVar9 + 0x24) != (code *)0x0) {
            (**(code **)(iVar9 + 0x24))(0,uVar11,piVar3[1],uVar11);
          }
          iVar9 = *(int *)(iVar8 + 0x28);
          piVar3[1] = iVar9;
          mmgsdi_handler_continue(piVar3,uVar11,uVar11,iVar9);
          unaff_r20 = 0;
          iVar9 = piVar3[1];
          iVar8 = *(int *)(*(int *)(iVar8 + 8) + iVar9 * 0x10 + 0xc);
          if (iVar8 == 0) {
            sVar1 = -1;
          }
          else {
            sVar1 = 0;
          }
          if (sVar1 == 0) {
            iVar9 = *piVar3;
          }
          if (iVar8 != 0) {
            sVar1 = mmgsdi_generic_handler(iVar8 + *(int *)(iVar9 + 0xc) * 0x1c);
            if (sVar1 == 0) {
              sVar10 = -1;
            }
            else {
              sVar10 = 0;
            }
            if (sVar10 == 0) {
              mmgsdi_handler_notify();
              piVar3[1] = -0x82;
              mmgsdi_handler_complete();
              pcVar7 = *(code **)(*(int *)*piVar3 + 0x20);
              if (pcVar7 == (code *)0x0) {
                sVar10 = -1;
              }
              else {
                sVar10 = 0;
              }
              unaff_r20 = 0;
              if (sVar10 != 0) {
                unaff_r20 = sVar1;
              }
              if (pcVar7 == (code *)0x0) {
                err_fatal(&UNK_c1bf42f4);
              }
              else {
                (*pcVar7)();
                unaff_r20 = sVar1;
              }
            }
          }
          func_0xc1736128(piVar3);
          goto code_r0xc1736104;
        }
      }
    }
  }
  piVar3 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b6a;
  if (piVar3 != (int *)0x0) {
    puVar2 = &UNK_c3478b74;
    if ((int *)*piVar3 != (int *)0x0) {
      iVar8 = *(int *)*piVar3;
      puVar2 = &UNK_c3478b7e;
      if (iVar8 != 0) {
        puVar2 = (undefined *)(*(int *)(iVar8 + 8) + piVar3[1] * 0x10);
        if (*(code **)(puVar2 + 4) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(puVar2 + 4))(piVar3,extraout_r1,param_1);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(iVar8 + 0x24))();
        }
        return puVar2;
      }
    }
  }
  piVar3 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b4c;
  if (piVar3 != (int *)0x0) {
    puVar2 = &UNK_c3478b56;
    if ((int *)*piVar3 != (int *)0x0) {
      iVar8 = *(int *)*piVar3;
      puVar2 = &UNK_c3478b60;
      if (iVar8 != 0) {
        puVar2 = (undefined *)(*(int *)(iVar8 + 8) + piVar3[1] * 0x10);
        if (*(code **)(puVar2 + 8) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(puVar2 + 8))(piVar3,extraout_r1_00,param_1);
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          puVar2 = (undefined *)(**(code **)(iVar8 + 0x24))();
        }
        return puVar2;
      }
    }
  }
  piVar3 = (int *)msg_send_3(puVar2);
  puVar2 = &UNK_c3478b2e;
  uVar11 = extraout_r1_00;
  if (piVar3 != (int *)0x0) {
    puVar2 = &UNK_c3478b38;
    if ((int *)*piVar3 != (int *)0x0) {
      iVar8 = *(int *)*piVar3;
      puVar4 = &UNK_c3478b42;
      puVar2 = &UNK_c3478b42;
      if (iVar8 == 0) {
        sVar1 = -1;
      }
      else {
        sVar1 = 0;
      }
      if (sVar1 == 0) {
        param_1 = *(code **)(iVar8 + 0x1c);
      }
      if (iVar8 != 0) {
        if (param_1 != (code *)0x0) {
          puVar4 = (undefined *)(*param_1)();
        }
        if (*(code **)(iVar8 + 0x24) != (code *)0x0) {
          puVar4 = (undefined *)
                   (**(code **)(iVar8 + 0x24))(2,extraout_r1_01,piVar3[1],extraout_r1_01);
        }
        return puVar4;
      }
      uVar11 = 0;
    }
  }
  sVar1 = (sbyte)uVar11;
  piVar3 = (int *)msg_send_3(puVar2);
  if (piVar3 != (int *)0x0) {
    piVar6 = (int *)func_0xc1735f64(piVar3);
    if (piVar6 == (int *)0x0) {
      sVar1 = -1;
    }
    else {
      sVar1 = 0;
    }
    piVar5 = piVar6;
    if (sVar1 != 0) {
      piVar5 = (int *)*piVar3;
    }
    if (piVar6 == (int *)0x0) {
      if (*(code **)(*piVar5 + 0x20) == (code *)0x0) {
        sVar1 = -2;
        err_fatal();
      }
      else {
        sVar1 = -2;
        (**(code **)(*piVar5 + 0x20))();
      }
    }
    else {
      sVar1 = mmgsdi_alt_dispatch();
    }
    return (undefined *)(int)sVar1;
  }
  piVar3 = (int *)msg_send_3(&UNK_c3478976);
  puVar2 = &UNK_c3478980;
  if (piVar3 == (int *)0x0) {
LAB_c1736444:
    iVar8 = msg_send_3(puVar2);
    if (5 < iVar8 + 5U) {
      return &UNK_c1f8b49f;
    }
    return *(undefined **)(&UNK_c1f8b4e0 + (iVar8 + 5U) * 4);
  }
  puVar2 = &UNK_c347898a;
  if (((int *)*piVar3 == (int *)0x0) || (puVar2 = &UNK_c3478994, *(int *)*piVar3 == 0))
  goto LAB_c1736444;
  sVar10 = func_0xc173644c(piVar3);
  if (sVar10 == 0) {
    sVar10 = -1;
  }
  else {
    sVar10 = 0;
  }
  if (sVar10 == 0) {
    pcVar7 = *(code **)(*(int *)*piVar3 + 0x20);
    if (pcVar7 == (code *)0x0) {
      sVar10 = -1;
    }
    else {
      sVar10 = 0;
    }
    if (sVar10 == 0) {
      sVar1 = -1;
    }
    if (pcVar7 == (code *)0x0) {
      sVar1 = -1;
      err_fatal(&UNK_c1bf4314);
    }
    else {
      (*pcVar7)();
    }
    goto LAB_c1736438;
  }
  if (piVar3[1] == -2) {
    sVar1 = 0;
    func_0xc1736454(piVar3);
    goto LAB_c1736438;
  }
  piVar6 = (int *)*piVar3;
  iVar8 = *(int *)(*(int *)(*piVar6 + 8) + piVar3[1] * 0x10 + 0xc);
  if (iVar8 == 0) {
    sVar1 = -1;
  }
  else {
    sVar1 = 0;
  }
  if (sVar1 == 0) {
    piVar6 = (int *)piVar6[3];
  }
  if (iVar8 == 0) {
LAB_c17363d8:
    mmgsdi_handler_notify(piVar3,extraout_r1_02,extraout_r1_02);
    sVar1 = 0;
    piVar3[1] = -0x82;
    mmgsdi_handler_complete();
  }
  else {
    sVar1 = mmgsdi_alt_dispatch(iVar8 + (int)piVar6 * 0x1c);
    if (sVar1 == 0) {
      sVar10 = -1;
    }
    else {
      sVar10 = 0;
    }
    if (sVar10 != 0) goto LAB_c17363d8;
    if (*(code **)(*(int *)*piVar3 + 0x20) == (code *)0x0) {
      err_fatal(&UNK_c1bf4324);
    }
    else {
      (**(code **)(*(int *)*piVar3 + 0x20))();
    }
  }
  func_0xc173645c(piVar3);
LAB_c1736438:
  return (undefined *)(int)sVar1;
}




Done.
