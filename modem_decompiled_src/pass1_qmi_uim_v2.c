pass1: QMI UIM layer — restriction check, open_logical_channel

Opening existing project: /tmp/ghidra_modem_project/modem

======================================================================
[qmi_uim_restriction_check] @ 0xC0A16DA8 (1936 bytes)
======================================================================


uint qmi_uim_restriction_check(int param_1)

{
  undefined *puVar1;
  undefined *puVar2;
  uint uVar3;
  int iVar4;
  uint uVar5;
  int iVar6;
  uint extraout_r1;
  uint extraout_r1_00;
  undefined4 extraout_r1_01;
  int extraout_r1_02;
  undefined4 *puVar7;
  uint extraout_r1_03;
  undefined4 *extraout_r1_04;
  int extraout_r1_05;
  uint extraout_r1_06;
  int iVar8;
  undefined4 *puVar9;
  undefined4 *puVar10;
  undefined4 *in_r4;
  undefined4 *puVar11;
  undefined *unaff_r16;
  int iVar12;
  undefined4 *unaff_r17;
  undefined4 *unaff_r18;
  int unaff_r19;
  int unaff_r20;
  undefined4 unaff_r21;
  ulonglong in_r23r22;
  ulonglong in_r25r24;
  ulonglong in_r27r26;
  undefined4 *puVar13;
  undefined4 uVar14;
  undefined4 uVar15;
  int in_GP;
  sbyte sVar16;
  short sVar17;
  ushort uVar18;
  
  puVar9 = (undefined4 *)&stack0xfffffff8;
  puVar1 = &UNK_c3454d80;
  if (*(int *)(&UNK_c2da5620 + param_1 * 4) != 0) {
    iVar6 = *(int *)(*(int *)(&UNK_c2da5620 + param_1 * 4) + 4);
    puVar1 = &UNK_c3454d8a;
    if (iVar6 != 0) {
      return *(uint *)(iVar6 + 0x7b8);
    }
  }
  uVar14 = 0xc0a16dd8;
  puVar1 = (undefined *)msg_send_3(puVar1);
  uVar3 = extraout_r1;
  puVar11 = puVar9;
SUB_c0a16dd8:
  do {
    puVar10 = puVar9 + -2;
    puVar9[-1] = uVar14;
    *puVar10 = puVar11;
    puVar2 = &UNK_c3454d4e;
    iVar6 = *(int *)(&UNK_c2da5620 + (int)puVar1 * 4);
    if (iVar6 == 0) {
LAB_c0a16e68:
      msg_send_3(puVar2);
    }
    else {
      in_r4 = *(undefined4 **)(iVar6 + 4);
      puVar2 = &UNK_c3454d58;
      if (in_r4 == (undefined4 *)0x0) goto LAB_c0a16e68;
      if ((in_r4[0x1ee] & uVar3) == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      if ((((sVar16 != 0) || (uVar3 == 8)) || (uVar3 == 0x100)) ||
         ((uVar3 == 0x4000 || (uVar3 == 0x400000)))) {
        in_r4[0x1ee] = in_r4[0x1ee] | uVar3;
        if (**(sbyte **)(in_GP + 0x266) != 1) {
          if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          if (sVar16 != 0) {
            return **(uint **)(in_GP + 0x4a30);
          }
          if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          if (sVar16 != 0) {
            return **(uint **)(in_GP + 0x4a34);
          }
        }
        uVar3 = log_3arg(&UNK_c1b69078,uVar3,*(undefined4 *)(*(int *)(iVar6 + 4) + 0x7b8));
        return uVar3;
      }
    }
    uVar14 = 0xc0a16e78;
    iVar4 = msg_send_2(&UNK_c3454d62);
    puVar1 = &UNK_c3454d26;
    puVar11 = puVar9 + -4;
    puVar9[-3] = uVar14;
    *puVar11 = puVar10;
    puVar9[-6] = unaff_r16;
    puVar9[-5] = unaff_r17;
    iVar12 = *(int *)(&UNK_c2da5620 + iVar4 * 4);
    if (iVar12 != 0) {
      iVar8 = *(int *)(iVar12 + 4);
      puVar1 = &UNK_c3454d30;
      if (iVar8 == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      if (sVar16 == 0) {
        puVar1 = (undefined *)(uint)*(char *)(iVar8 + 0x8b0);
      }
      if (iVar8 != 0) {
        if (puVar1 == (undefined *)0x1) {
          qmi_uim_dispatch(iVar4,iVar8 + 0x8b4);
          func_0xc0a15690(iVar12);
        }
        uVar3 = 0x19;
        uVar14 = puVar9[-5];
        iVar4 = puVar9[-6];
        uVar15 = puVar9[-3];
        puVar9 = (undefined4 *)*puVar11;
code_r0xc09aae10:
        puVar10[-1] = uVar15;
        puVar10[-2] = puVar9;
        puVar10[-4] = iVar4;
        puVar10[-3] = uVar14;
        uVar14 = get_current_task();
        if (uVar3 < 0x21) {
          uVar3 = (**(code **)(**(int **)(in_GP + 0xa5ec) + uVar3 * 4))(uVar14,&UNK_c2da40d9);
          return uVar3;
        }
        if (**(sbyte **)(in_GP + 0x266) != 1) {
          if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          if (sVar16 != 0) {
            return **(uint **)(in_GP + 0x4a30);
          }
          if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          if (sVar16 != 0) {
            return **(uint **)(in_GP + 0x4a34);
          }
        }
        uVar3 = log_2arg();
        return uVar3;
      }
    }
    uVar14 = 0xc0a16ecc;
    iVar4 = msg_send_3(puVar1);
    puVar10 = puVar9 + -8;
    puVar9[-7] = uVar14;
    *puVar10 = puVar11;
    puVar1 = &UNK_c3454d3a;
    if (*(int *)(&UNK_c2da5620 + iVar4 * 4) != 0) {
      iVar4 = *(int *)(*(int *)(&UNK_c2da5620 + iVar4 * 4) + 4);
      puVar1 = &UNK_c3454d44;
      if (iVar4 != 0) {
        return (uint)*(char *)(iVar4 + 0x8b0);
      }
    }
    uVar14 = 0xc0a16f00;
    uVar5 = msg_send_3(puVar1);
    uVar3 = extraout_r1_00;
    puVar13 = puVar10;
    while( true ) {
      puVar13[-1] = uVar14;
      puVar13[-2] = puVar10;
      puVar1 = &UNK_c3454d6c;
      iVar4 = *(int *)(&UNK_c2da5620 + uVar5 * 4);
      if (iVar4 != 0) {
        iVar6 = *(int *)(iVar4 + 4);
        puVar1 = &UNK_c3454d76;
        if (iVar6 == 0) {
          sVar16 = -1;
        }
        else {
          sVar16 = 0;
        }
        if (sVar16 == 0) {
          in_r4 = (undefined4 *)0xffffffff;
        }
        if (iVar6 != 0) {
          *(uint *)(iVar6 + 0x7b8) = *(uint *)(iVar6 + 0x7b8) & (uVar3 ^ (uint)in_r4);
          if (**(sbyte **)(in_GP + 0x266) != 1) {
            if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 != 0) {
              return **(uint **)(in_GP + 0x4a30);
            }
            if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 != 0) {
              return **(uint **)(in_GP + 0x4a34);
            }
          }
          uVar3 = log_3arg(&UNK_c1b69080,uVar3,*(undefined4 *)(*(int *)(iVar4 + 4) + 0x7b8));
          return uVar3;
        }
        iVar6 = 0;
      }
      uVar14 = 0xc0a16f6c;
      iVar4 = msg_send_3(puVar1);
      puVar9 = puVar13 + -4;
      puVar13[-3] = uVar14;
      *puVar9 = puVar13 + -2;
      puVar10 = puVar13 + -8;
      puVar13[-6] = iVar12;
      puVar13[-5] = unaff_r17;
      puVar13[-8] = unaff_r18;
      puVar13[-7] = unaff_r19;
      unaff_r18 = (undefined4 *)&UNK_c3454d94;
      unaff_r19 = *(int *)(&UNK_c2da5620 + iVar4 * 4);
      if ((unaff_r19 != 0) &&
         (unaff_r18 = (undefined4 *)&UNK_c3454d9e, *(int *)(unaff_r19 + 4) != 0)) {
        uVar3 = 0x1c;
        uVar15 = 0xc0a16fa0;
        uVar14 = extraout_r1_01;
        goto code_r0xc09aae10;
      }
      uVar14 = 0xc0a17040;
      iVar12 = unaff_r19;
      uVar5 = msg_send_3(unaff_r18);
      puVar10 = puVar13 + -10;
      puVar13[-9] = uVar14;
      *puVar10 = puVar9;
      puVar13[-0xc] = iVar4;
      puVar13[-0xb] = extraout_r1_01;
      uVar3 = *(uint *)(&UNK_c2da5620 + uVar5 * 4);
      puVar13[-0xe] = unaff_r18;
      puVar13[-0xd] = iVar12;
      puVar1 = &UNK_c3454db2;
      if (uVar3 == 0) break;
      iVar6 = *(int *)(uVar3 + 4);
      puVar1 = &UNK_c3454dbc;
      if (iVar6 == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      if (sVar16 == 0) {
        unaff_r18 = (undefined4 *)0x0;
      }
      if (iVar6 == 0) break;
      unaff_r17 = *(undefined4 **)(iVar6 + 0x7c0);
      if (unaff_r17 != (undefined4 *)0x0) {
        puVar11 = (undefined4 *)0x7c4;
        puVar9 = (undefined4 *)0x1;
LAB_c0a17080:
        unaff_r18 = puVar9;
        if ((*(int *)((int)puVar11 + iVar6 + 8) != *(int *)(extraout_r1_02 + 0xc)) ||
           (*(short *)((int)puVar11 + iVar6 + 4) != *(short *)(extraout_r1_02 + 8)))
        goto LAB_c0a170ec;
        if (unaff_r18 < unaff_r17) {
          sVar16 = -1;
        }
        else {
          sVar16 = 0;
        }
        if (sVar16 == 0) {
          puVar11 = unaff_r17;
        }
        if (unaff_r18 < unaff_r17) {
          iVar12 = (int)unaff_r17 - (int)unaff_r18;
          while( true ) {
            puVar9 = (undefined4 *)(iVar6 + (int)puVar11);
            iVar12 = iVar12 + -1;
            puVar9[2] = puVar9[5];
            puVar9[1] = puVar9[4];
            *puVar9 = puVar9[3];
            if (iVar12 == 0) break;
            iVar6 = *(int *)(uVar3 + 4);
            puVar11 = puVar11 + 3;
          }
          iVar6 = *(int *)(uVar3 + 4);
          puVar11 = *(undefined4 **)(iVar6 + 0x7c0);
        }
        in_r4 = (undefined4 *)((int)puVar11 + -1);
        unaff_r18 = (undefined4 *)((int)unaff_r18 + -1);
        *(undefined4 **)(iVar6 + 0x7c0) = in_r4;
        puVar7 = *(undefined4 **)(*(int *)(uVar3 + 4) + 0x7c0);
LAB_c0a170f8:
        if (puVar7 != (undefined4 *)0x0) {
          if (unaff_r18 != unaff_r17) {
            return uVar5;
          }
          if (**(sbyte **)(in_GP + 0x266) != 1) {
            if ((**(uint **)(in_GP + 0x4a30) & 8) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 != 0) {
              return **(uint **)(in_GP + 0x4a30);
            }
            if ((**(uint **)(in_GP + 0x4a34) & 8) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 != 0) {
              return **(uint **)(in_GP + 0x4a34);
            }
          }
          uVar3 = log_3arg(&UNK_c1b69098,*(undefined4 *)(extraout_r1_02 + 0xc),
                           *(undefined2 *)(extraout_r1_02 + 8),iVar6,in_r4);
          return uVar3;
        }
      }
      uVar3 = 8;
      uVar14 = 0xc0a17104;
      iVar12 = extraout_r1_02;
      puVar13 = puVar13 + -0xe;
    }
    uVar14 = 0xc0a17148;
    iVar12 = msg_send_3(puVar1);
    puVar13[-0xf] = uVar14;
    puVar13[-0x10] = puVar10;
    puVar1 = &UNK_c3454dc6;
    if (*(int *)(&UNK_c2da5620 + iVar12 * 4) != 0) {
      iVar12 = *(int *)(*(int *)(&UNK_c2da5620 + iVar12 * 4) + 4);
      puVar1 = &UNK_c3454dd0;
      if (iVar12 != 0) {
        uVar3 = iVar12 + 0x7c0;
        if (*(int *)(iVar12 + 0x7c0) == 0) {
          sVar16 = -1;
        }
        else {
          sVar16 = 0;
        }
        if (sVar16 != 0) {
          uVar3 = 0;
        }
        return uVar3;
      }
    }
    uVar14 = 0xc0a17180;
    iVar12 = msg_send_3(puVar1);
    puVar13[-0x11] = uVar14;
    puVar13[-0x12] = puVar13 + -0x10;
    iVar12 = *(int *)(&UNK_c2da5620 + iVar12 * 4);
    puVar13[-0x13] = extraout_r1_01;
    puVar13[-0x14] = extraout_r1_02;
    puVar13[-0x16] = unaff_r18;
    puVar13[-0x15] = unaff_r19;
    puVar1 = &UNK_c3454dda;
    uVar5 = uVar3;
    if (((iVar12 != 0) && (puVar1 = &UNK_c3454de4, iVar6 != 0)) &&
       (puVar1 = &UNK_c3454dee, *(int *)(iVar12 + 4) != 0)) {
      if (uVar3 < 7) {
        uVar3 = (**(code **)(**(int **)(in_GP + 0xa68c) + uVar3 * 4))();
        return uVar3;
      }
      if ((extraout_r1_03 & 2) == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      *(sbyte *)((int)puVar13 + -0x62) = (sbyte)uVar3;
      if (sVar16 == 0) {
        puVar1 = &UNK_c3454e02;
        unaff_r18 = (undefined4 *)&UNK_c31cdfd8;
        if (_UNK_c31cdfd8 == (code *)0x0) goto LAB_c0a172e8;
        (*_UNK_c31cdfd8)(puVar13 + -0x1a);
      }
      if ((extraout_r1_03 & 0x40) == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      if (sVar16 == 0) {
        puVar1 = &UNK_c3454e0c;
        unaff_r18 = (undefined4 *)&UNK_c31cdfd8;
        if (_UNK_c31cdff0 == (code *)0x0) goto LAB_c0a172e8;
        (*_UNK_c31cdff0)(puVar13 + -0x1a);
      }
      if ((extraout_r1_03 & 0x800) == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      if (sVar16 != 0) {
LAB_c0a172c0:
        uVar3 = extraout_r1_03 & 0x842;
        if (uVar3 == 0) {
          log_4arg();
          uVar3 = func_0xc0aaf0e0();
        }
        return uVar3;
      }
      puVar1 = &UNK_c3454e16;
      unaff_r18 = (undefined4 *)&UNK_c31cdfd8;
      if (_UNK_c31cdff8 != (code *)0x0) {
        (*_UNK_c31cdff8)(puVar13 + -0x1a);
        goto LAB_c0a172c0;
      }
    }
LAB_c0a172e8:
    uVar14 = 0xc0a172ec;
    unaff_r16 = (undefined *)msg_send_3(puVar1);
    puVar11 = puVar13 + -0x1c;
    puVar13[-0x1b] = uVar14;
    *puVar11 = puVar13 + -0x12;
    puVar9 = puVar13 + -0x28;
    puVar13[-0x1e] = extraout_r1_03;
    puVar13[-0x1d] = uVar3;
    puVar13[-0x22] = unaff_r20;
    puVar13[-0x21] = unaff_r21;
    puVar1 = &UNK_c3454e20;
    unaff_r20 = *(int *)(&UNK_c2da5620 + (int)unaff_r16 * 4);
    puVar13[-0x1f] = unaff_r19;
    puVar13[-0x20] = unaff_r18;
    puVar13[-0x23] = (int)(in_r23r22 >> 0x20);
    puVar13[-0x24] = (int)in_r23r22;
    puVar13[-0x25] = (int)(in_r25r24 >> 0x20);
    puVar13[-0x26] = (int)in_r25r24;
    puVar13[-0x27] = (int)(in_r27r26 >> 0x20);
    puVar13[-0x28] = (int)in_r27r26;
    unaff_r17 = extraout_r1_04;
    if (unaff_r20 != 0) {
      if (*(int *)(unaff_r20 + 4) == 0) {
        sVar16 = -1;
      }
      else {
        sVar16 = 0;
      }
      puVar1 = &UNK_c3454e2a;
      if (sVar16 == 0) {
        puVar1 = unaff_r16;
      }
      if (*(int *)(unaff_r20 + 4) != 0) {
        unaff_r18 = (undefined4 *)func_0xc0924774(puVar1);
        iVar6 = *(int *)(unaff_r20 + 4);
        sVar17 = (short)extraout_r1_05;
        uVar18 = (ushort)((uint)extraout_r1_05 >> 0x10);
        in_r27r26 = (ulonglong)uVar18;
        in_r23r22 = CONCAT26(uVar18,CONCAT24(sVar17,unaff_r18)) >> 0x10;
        uVar14 = extraout_r1_04[1];
        *(undefined4 *)(iVar6 + 0x880) = *extraout_r1_04;
        in_r25r24 = CONCAT26(uVar18,CONCAT24(sVar17,unaff_r18)) >> 8;
        *(undefined4 *)(iVar6 + 0x884) = uVar14;
        puVar10 = (undefined4 *)extraout_r1_04[2];
        iVar6 = *(int *)(unaff_r20 + 4);
        *(undefined4 *)(iVar6 + 0x894) = puVar10[3];
        *(undefined4 *)(iVar6 + 0x890) = puVar10[2];
        in_r4 = (undefined4 *)puVar10[1];
        *(undefined4 **)(iVar6 + 0x88c) = in_r4;
        *(undefined4 *)(iVar6 + 0x888) = *puVar10;
        *(bool *)(*(int *)(unaff_r20 + 4) + 0x899) = *(sbyte *)((int)extraout_r1_04 + 0xd) == 0;
        if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a173a8:
          log_4arg(&UNK_c1b690a8,(uint)unaff_r18 & 0xff,sVar17,(sbyte)((uint)unaff_r18 >> 8),in_r4);
        }
        else {
          if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          if (sVar16 == 0) {
            if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 == 0) goto LAB_c0a173a8;
          }
        }
        if ((sbyte)unaff_r18 == 0) {
          sVar16 = -1;
        }
        else {
          sVar16 = 0;
        }
        if (sVar16 == 0) {
          if ((int)sVar17 < *(int *)(*(int *)(unaff_r20 + 4) + 0x888)) {
            *(int *)(*(int *)(unaff_r20 + 4) + 0x888) = (int)(short)in_r27r26;
          }
          if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a173f8:
            log_4arg(&UNK_c1b690b0,(short)in_r27r26,*(undefined4 *)extraout_r1_04[2],
                     *(undefined4 *)(*(int *)(unaff_r20 + 4) + 0x888));
          }
          else {
            if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 == 0) {
              if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
                sVar16 = -1;
              }
              else {
                sVar16 = 0;
              }
              if (sVar16 == 0) goto LAB_c0a173f8;
            }
          }
          if ((sbyte)in_r25r24 < *(sbyte *)(*(int *)(unaff_r20 + 4) + 0x893)) {
            *(sbyte *)(*(int *)(unaff_r20 + 4) + 0x893) = (sbyte)in_r23r22;
          }
          if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a1744c:
            in_r4 = *(undefined4 **)(unaff_r20 + 4);
            log_4arg(&UNK_c1b690b8,(sbyte)in_r23r22,*(undefined1 *)(extraout_r1_04[2] + 0xb),
                     *(undefined *)((int)in_r4 + 0x893));
          }
          else {
            if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
              sVar16 = -1;
            }
            else {
              sVar16 = 0;
            }
            if (sVar16 == 0) {
              if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
                sVar16 = -1;
              }
              else {
                sVar16 = 0;
              }
              if (sVar16 == 0) goto LAB_c0a1744c;
            }
          }
        }
        *(undefined1 *)(*(int *)(unaff_r20 + 4) + 0x898) = *(undefined1 *)(extraout_r1_04 + 3);
        *(undefined *)(*(int *)(unaff_r20 + 4) + 0x89a) = *(undefined *)((int)extraout_r1_04 + 0xe);
        uVar3 = qmi_uim_restriction_check(unaff_r16);
        if ((uVar3 & 4) != 0) {
          return uVar3 & 4;
        }
        uVar3 = 4;
        uVar14 = 0xc0a174a0;
        puVar1 = unaff_r16;
        unaff_r19 = extraout_r1_05;
        goto SUB_c0a16dd8;
      }
    }
    uVar14 = 0xc0a174b8;
    iVar6 = msg_send_3(puVar1);
    puVar13[-0x29] = uVar14;
    puVar13[-0x2a] = puVar11;
    puVar1 = &UNK_c3454e34;
    if (*(int *)(&UNK_c2da5620 + iVar6 * 4) != 0) {
      iVar6 = *(int *)(*(int *)(&UNK_c2da5620 + iVar6 * 4) + 4);
      puVar1 = &UNK_c3454e3e;
      if (iVar6 != 0) {
        return iVar6 + 0x880;
      }
    }
    uVar14 = 0xc0a174e8;
    iVar6 = msg_send_3(puVar1);
    puVar13[-0x2b] = uVar14;
    puVar13[-0x2c] = puVar13 + -0x2a;
    puVar1 = &UNK_c3454e48;
    if (*(int *)(&UNK_c2da5620 + iVar6 * 4) != 0) {
      iVar6 = *(int *)(*(int *)(&UNK_c2da5620 + iVar6 * 4) + 4);
      puVar1 = &UNK_c3454e52;
      if (iVar6 != 0) {
        return iVar6 + 0x888;
      }
    }
    uVar14 = 0xc0a17518;
    iVar6 = msg_send_3(puVar1);
    puVar13[-0x2d] = uVar14;
    puVar13[-0x2e] = puVar13 + -0x2c;
    puVar1 = &UNK_c3454e5c;
    if (*(int *)(&UNK_c2da5620 + iVar6 * 4) != 0) {
      iVar6 = *(int *)(*(int *)(&UNK_c2da5620 + iVar6 * 4) + 4);
      puVar1 = &UNK_c3454e66;
      if (iVar6 != 0) {
        return (uint)*(char *)(iVar6 + 0x898);
      }
    }
    uVar14 = 0xc0a1754c;
    iVar6 = msg_send_3(puVar1);
    puVar13[-0x2f] = uVar14;
    puVar13[-0x30] = puVar13 + -0x2e;
    puVar1 = &UNK_c3454e70;
    if (*(int *)(&UNK_c2da5620 + iVar6 * 4) != 0) {
      iVar6 = *(int *)(*(int *)(&UNK_c2da5620 + iVar6 * 4) + 4);
      puVar1 = &UNK_c3454e7a;
      if (iVar6 != 0) {
        return (uint)*(char *)(iVar6 + 0x89a);
      }
    }
    uVar14 = 0xc0a17580;
    puVar1 = (undefined *)msg_send_3(puVar1);
    puVar9 = puVar13 + -0x32;
    puVar13[-0x31] = uVar14;
    *puVar9 = puVar13 + -0x30;
    puVar2 = &UNK_c3454e84;
    if (*(int *)(&UNK_c2da5620 + (int)puVar1 * 4) == 0) {
LAB_c0a175b4:
      puVar1 = (undefined *)msg_send_3(puVar2);
LAB_c0a175bc:
      uVar3 = func_0xc0a16dd8(puVar1,0x200000);
      return uVar3;
    }
    in_r4 = *(undefined4 **)(*(int *)(&UNK_c2da5620 + (int)puVar1 * 4) + 4);
    puVar2 = &UNK_c3454e8e;
    if (in_r4 == (undefined4 *)0x0) goto LAB_c0a175b4;
    if (uVar5 == 1) {
      sVar16 = -1;
    }
    else {
      sVar16 = 0;
    }
    in_r4[0x227] = extraout_r1_06;
    uVar3 = extraout_r1_06;
    if (sVar16 == 0) {
      uVar3 = 0x10;
    }
    if (uVar5 == 1) goto LAB_c0a175bc;
    uVar14 = 0xc0a175b0;
    puVar11 = puVar9;
  } while( true );
LAB_c0a170ec:
  in_r4 = puVar11 + 3;
  puVar11 = puVar11 + 3;
  puVar7 = unaff_r17;
  puVar9 = (undefined4 *)((int)unaff_r18 + 1);
  if (unaff_r17 <= unaff_r18) goto LAB_c0a170f8;
  goto LAB_c0a17080;
}



======================================================================
[qmi_uim_open_logical_channel] @ 0xC0A15234 (412 bytes)
======================================================================


uint qmi_uim_open_logical_channel(ushort param_1,int param_2,uint param_3)

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
  
  iVar2 = get_current_task();
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
    iVar3 = qmi_uim_session_check_thunk(iVar2,param_1);
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
    uVar6 = qmi_uim_restriction_check(iVar4);
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
        uVar6 = qmi_uim_restriction_check(iVar2);
        if ((uVar6 & 0x100) == 0) {
          sVar8 = -1;
        }
        else {
          sVar8 = 0;
        }
        uVar6 = 1;
        if ((sVar8 == 0) &&
           ((iVar3 = lpa_is_idle(), iVar3 != 0 || (iVar3 = lpa_is_state8(), iVar3 != 0))))
        goto LAB_c0a15304;
      }
      iVar3 = qmi_uim_session_check_thunk(iVar2,uStack_2e);
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
  uVar5 = qmi_uim_session_check_thunk();
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
  uStack_48 = qmi_uim_restriction_check(iVar2);
  uStack_58 = uVar7;
  uStack_54 = uVar5;
  uStack_50 = uVar6;
  uStack_4c = (uint)cVar1;
  log_narg();
LAB_c0a1535c:
  signal_init(auStack_40,0x402,0x4020200);
  iVar2 = signal_wait(auStack_40,0x20);
  if (iVar2 == 0) {
    return uVar6;
  }
  uVar5 = 0xc0a15390;
  uStack_6e = msg_send_3(&UNK_c3454bb4);
  uStack_70 = 4;
  puStack_60 = &stack0xfffffff8;
  uStack_5c = uVar5;
  signal_init(auStack_80,0x402);
  iVar2 = signal_wait(auStack_80,0x20);
  if (iVar2 == 0) {
    return 0;
  }
  msg_send_3(&UNK_c3454bbe);
  iVar2 = signal_state_read(0xc2149db0);
  return (uint)(iVar2 != -2);
}



======================================================================
[qmi_uim_aid_check] @ 0xC0985CC4 (120 bytes)
======================================================================


undefined4 qmi_uim_aid_check(undefined4 param_1,int param_2)

{
  int iVar1;
  int iVar2;
  int in_GP;
  sbyte sVar3;
  
  iVar1 = session_state_byte();
  if ((iVar1 == param_2) || (iVar2 = qmi_uim_aid_compare(), iVar2 != 0)) {
    qmi_uim_aid_match_handler();
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
  log_3arg(&UNK_c1b64848,iVar1,param_2);
  return 0;
}



======================================================================
[qmi_uim_check_result_not_denied] @ 0xC0A153D0 (20 bytes)
======================================================================

bool qmi_uim_check_result_not_denied(void)

{
  int iVar1;
  
  iVar1 = signal_state_read(0xc2149db0);
  return iVar1 != -2;
}



======================================================================
[qmi_uim_process_result] @ 0xC0A153E4 (936 bytes)
======================================================================

/* WARNING (jumptable): Heritage AFTER dead removal. Revisit: 0x00000000 */

undefined4 qmi_uim_process_result(void)

{
  signal_state_read(&uRamc2149db0);
  session_dispatch();
  return 1;
}




Done.
