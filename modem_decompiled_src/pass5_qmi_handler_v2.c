pass5: QMI UIM main handler — dispatch, setup, result processing

Opening existing project: /tmp/ghidra_modem_project/modem

======================================================================
[qmi_uim_dispatch] @ 0xC0A07700 (288 bytes)
======================================================================

/* WARNING (jumptable): Heritage AFTER dead removal. Revisit: 0x00000000 */

void qmi_uim_dispatch(void)

{
  uint uVar1;
  ushort uVar2;
  sbyte sVar3;
  sbyte *psVar4;
  ulonglong in_r1r0;
  ushort *puVar7;
  ulonglong uVar5;
  uint uVar8;
  ulonglong uVar6;
  undefined1 *puVar9;
  uint uVar10;
  uint uVar11;
  int iVar12;
  uint uVar13;
  uint unaff_r20;
  undefined4 *puVar14;
  uint unaff_r22;
  uint unaff_r23;
  uint unaff_r24;
  undefined4 *unaff_r26;
  ushort *unaff_r27;
  int in_GP;
  sbyte sVar15;
  sbyte sVar16;
  uint uVar17;
  uint uStack_148;
  uint uStack_144;
  int iStack_134;
  uint uStack_12c;
  sbyte sStack_128;
  undefined1 uStack_119;
  undefined1 auStack_118 [200];
  
  iVar12 = (int)in_r1r0;
  puVar7 = (ushort *)(in_r1r0 >> 0x20);
  qmi_uim_restriction_check();
  uVar5 = CONCAT44(&UNK_c3453fca,iVar12);
  uVar13 = *(uint *)(&UNK_c2da5600 + iVar12 * 4);
  if ((uVar13 != 0) && (uVar5 = CONCAT44(&UNK_c3453fd4,iVar12), puVar7 != (ushort *)0x0)) {
    if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a07754:
      log_3arg(&UNK_c1b689b0,&UNK_c3453fd4,puVar7[1]);
    }
    else {
      if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
          sVar15 = -1;
        }
        else {
          sVar15 = 0;
        }
        if (sVar15 == 0) goto LAB_c0a07754;
      }
    }
    uVar5 = CONCAT44(&UNK_c3453fde,(int)(short)*puVar7);
    uVar2 = puVar7[1];
    if ((uVar2 & *puVar7) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 != 0) {
      if (uVar2 == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        func_0xc0a07450(iVar12,&UNK_c3453fde,uVar2);
        uVar5 = (ulonglong)(uint)(int)(short)*puVar7;
      }
      if ((short)uVar5 == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        qmi_uim_setup_1(iVar12);
        qmi_uim_setup_2();
        if ((*puVar7 & 0x3fc) == 0) goto LAB_c0a077c0;
      }
      else {
LAB_c0a077c0:
        if ((puVar7[1] & 0x3fc) == 0) {
          sVar15 = -1;
        }
        else {
          sVar15 = 0;
        }
        if (sVar15 != 0) goto LAB_c0a077d8;
      }
      qmi_uim_pre_dispatch(iVar12);
LAB_c0a077d8:
      qmi_uim_main_handler();
      if ((in_r1r0 & 0x20000) == 0) {
        func_0xc0a16dd8();
      }
      return;
    }
  }
  uVar8 = (uint)(uVar5 >> 0x20);
  msg_send_3(uVar8);
  uVar11 = *(uint *)(&UNK_c2da5600 + uVar8 * 4);
  qmi_uim_init_handler();
  iVar12 = (int)uVar5;
  uVar6 = CONCAT44(&UNK_c3454038,iVar12);
  uVar17 = uVar11;
  if (uVar11 == 0) goto LAB_c0a080c8;
  uVar6 = CONCAT44(&UNK_c3454042,iVar12);
  if (uVar8 == 0) goto LAB_c0a080c8;
  qmi_uim_get_request_info();
  sStack_128 = -(uVar8 == 0);
  unaff_r24 = uVar8;
  if (sStack_128 == 0) {
    *(undefined1 *)(uVar11 + 0x31) = 0;
    unaff_r24 = uVar8 + 1;
  }
  if (**(sbyte **)(in_GP + 0x266) != 1) {
    if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 != 0) goto LAB_c0a078cc;
    if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 != 0) goto LAB_c0a078cc;
  }
  func_0xc091a618(uVar8);
  log_4arg();
LAB_c0a078cc:
  if ((((*(char *)(uVar11 + 0x28) & '0') != 0) || (iVar12 != 0xff)) ||
     (*(sbyte *)(uVar11 + 0xa2c) == 0)) {
    if (*(sbyte *)(uVar11 + 0x30) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      unaff_r22 = 0;
    }
    uStack_12c = unaff_r22;
    if (*(sbyte *)(uVar11 + 0x30) != 0) {
LAB_c0a07904:
      iVar12 = uVar11 + uStack_12c * 0xc;
      puVar14 = *(undefined4 **)(iVar12 + 0x38);
      if (((puVar14 != *(undefined4 **)(uVar8 + 8)) || ((sbyte)(uVar5 >> 0x20) == 0)) ||
         ((*(uint *)(uVar11 + 0x24) & 1) == 0)) {
        func_0xc0a08630(puVar14);
        *(ushort *)(iVar12 + 0x36) = *(ushort *)(iVar12 + 0x36) & 0x80;
      }
      func_0xc09bfdb8();
      if (uVar8 == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      uVar13 = uVar8;
      if (sVar15 != 0) {
        uVar13 = puVar14[0x30];
      }
      if (uVar8 == 0) {
        func_0xc09c0790();
        psVar4 = (sbyte *)uVar6;
        if (uVar13 == 0) {
          sVar15 = *psVar4;
          if (sVar15 == 0) {
            sVar16 = -1;
          }
          else {
            sVar16 = 0;
          }
          sVar3 = sVar15;
          if (sVar16 == 0) {
            sVar3 = 0;
          }
          if (sVar15 == 0) {
            if ((*(char *)(uVar11 + 0x29) & '\x04') == 0) {
              sVar15 = -1;
            }
            else {
              sVar15 = 0;
            }
            uVar17 = uVar11;
            unaff_r23 = unaff_r24;
            if ((sVar15 != 0) || (func_0xc0a0c300(puVar14), sVar3 == 0)) {
              qmi_uim_init_handler(0);
              uVar6 = CONCAT44(&UNK_c3454812,psVar4);
              uVar13 = uVar11;
              unaff_r24 = uStack_12c * 0xc + uVar11 + 0x34;
              goto LAB_c0a080c8;
            }
            func_0xc0a10ef0(sVar3);
            if ((sVar3 == 0) || (func_0xc0a0c4f0(sVar3), sVar3 == 0)) {
              if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a07a34:
                log_narg();
              }
              else {
                if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
                  sVar15 = -1;
                }
                else {
                  sVar15 = 0;
                }
                if (sVar15 == 0) {
                  if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
                    sVar15 = -1;
                  }
                  else {
                    sVar15 = 0;
                  }
                  if (sVar15 == 0) goto LAB_c0a07a34;
                }
              }
              iVar12 = puVar14[0x36];
              unaff_r20 = 3;
              uVar13 = 1;
              uVar11 = 1;
              if ((unaff_r24 == puVar14[0x35]) && (puVar14[0x35] != 0)) goto LAB_c0a07eb8;
LAB_c0a07ec8:
              unaff_r20 = unaff_r20 | 1;
              uStack_144 = 1;
            }
            else {
              if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a079e8:
                log_2arg(&UNK_c1b68e40);
              }
              else {
                if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
                  sVar15 = -1;
                }
                else {
                  sVar15 = 0;
                }
                if (sVar15 == 0) {
                  if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
                    sVar15 = -1;
                  }
                  else {
                    sVar15 = 0;
                  }
                  if (sVar15 == 0) goto LAB_c0a079e8;
                }
              }
              uVar11 = 0;
              unaff_r20 = 0;
              uVar13 = 0;
              iVar12 = puVar14[0x36];
LAB_c0a07eb8:
              uStack_144 = uVar13;
              if (UNK_c2da5604 == 1) goto LAB_c0a07ec8;
            }
            unaff_r27 = (ushort *)0x0;
            if ((uVar11 != 0) && ((uVar11 <= iVar12 - unaff_r24 || (iVar12 == 0)))) {
              func_0xc0a08c50();
            }
            qmi_uim_init_handler(0);
            uVar6 = 0xc345481c00000000;
            unaff_r26 = (undefined4 *)0x0;
LAB_c0a080c8:
            do {
              uVar11 = unaff_r23;
              msg_send_3((int)(uVar6 >> 0x20));
              iVar12 = unaff_r26[0x35];
              func_0xc0a04ef0(uVar8);
              uVar1 = iVar12 + uVar8 * *unaff_r27;
              uVar10 = 1;
              if (uVar1 != unaff_r24) {
                if (unaff_r20 < uVar1) {
                  sVar15 = -1;
                }
                else {
                  sVar15 = 0;
                }
                if (sVar15 != 0) {
                  uVar10 = uVar17;
                }
                if ((uVar1 <= unaff_r20) && (uVar10 = uVar17, unaff_r24 < uVar1)) goto LAB_c0a08124;
              }
              do {
                uVar13 = uVar13 + 1;
                if ((uint)*(char *)(uVar11 + 0x30) <= (uVar13 & 0xff)) {
                  if ((sbyte)uVar10 == 0) {
                    sVar15 = -1;
                  }
                  else {
                    sVar15 = 0;
                  }
                  if (sVar15 == 0) {
                    uStack_144 = 1;
                  }
                  goto LAB_c0a08124;
                }
                uVar6 = (ulonglong)(uVar13 & 0xff);
                unaff_r26 = *(undefined4 **)(uVar11 + (uVar13 & 0xff) * 0xc + 0x38);
                func_0xc0a04fe8();
              } while (uVar8 != 3);
              uVar6 = CONCAT44(&UNK_c3454830,uVar13) & 0xffffffff000000ff;
              uVar17 = uVar10;
              unaff_r23 = uVar11;
              if (*(char *)*unaff_r26 < 6) {
                (**(code **)(**(int **)(in_GP + 0xa668) + (uint)*(char *)*unaff_r26 * 4))();
                return;
              }
            } while( true );
          }
          puVar9 = (undefined1 *)0xffffffff;
          func_0xc0a08678(sVar3);
          if (sVar3 == 0) {
            if (*psRam00000000 == 0) {
              func_0xc0a08580();
            }
            else {
              func_0xc0a08580();
            }
          }
          if (*(sbyte *)*puVar14 == 4) {
            sVar15 = -1;
          }
          else {
            sVar15 = 0;
          }
          if (sVar15 != 0) {
            puVar9 = &uStack_119;
          }
          if (*(sbyte *)*puVar14 == 4) {
            *puVar9 = 0;
            func_0xc09f8260(psVar4);
          }
        }
      }
      goto LAB_c0a082dc;
    }
  }
LAB_c0a082ec:
  if (sStack_128 == 0) {
    *(undefined1 *)(uVar11 + 0x31) = 0;
  }
  return;
LAB_c0a08124:
  func_0xc0a04dc0();
  func_0xc0a08580();
  if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a08158:
    func_0xc0a04dc0();
    log_narg();
    uVar6 = 0xc1b68e50;
  }
  else {
    if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) goto LAB_c0a08158;
    }
  }
  unaff_r20 = uStack_148;
  if ((((uStack_12c != 0) || ((sbyte)uVar6 != 0)) || (uStack_144 == 0 && iStack_134 == 0)) ||
     ((func_0xc0a163b8((int)uVar6), (int)uVar6 != 0 || (func_0xc0a1814c(), uVar8 != 0))))
  goto LAB_c0a082dc;
  func_0xc07158c0(auStack_118);
  func_0xc091a44c(0);
  if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a08230:
    log_3arg();
  }
  else {
    if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) goto LAB_c0a08230;
    }
  }
  func_0xc0ad9050();
  func_0xc099dfa0();
  func_0xc099dfb0();
  unaff_r20 = uVar11;
LAB_c0a082dc:
  uStack_12c = uStack_12c + 1;
  if (*(char *)(uVar11 + 0x30) <= uStack_12c) goto LAB_c0a082ec;
  goto LAB_c0a07904;
}



======================================================================
[qmi_uim_main_handler] @ 0xC0A07820 (2704 bytes)
======================================================================

/* WARNING (jumptable): Heritage AFTER dead removal. Revisit: 0x00000000 */

void qmi_uim_main_handler(void)

{
  sbyte sVar1;
  ushort uVar2;
  sbyte *psVar3;
  sbyte *psVar4;
  sbyte *psVar5;
  undefined8 in_r1r0;
  undefined *puVar6;
  int iVar7;
  undefined1 *puVar8;
  uint uVar9;
  sbyte *psVar10;
  sbyte *psVar11;
  sbyte *unaff_r19;
  sbyte *unaff_r20;
  undefined4 *puVar12;
  uint unaff_r22;
  sbyte *unaff_r23;
  sbyte *unaff_r24;
  undefined4 *unaff_r26;
  ushort *unaff_r27;
  int in_GP;
  sbyte sVar13;
  sbyte sVar14;
  sbyte *psStack_130;
  sbyte *psStack_12c;
  uint uStack_11c;
  uint uStack_114;
  sbyte sStack_110;
  undefined1 uStack_101;
  undefined1 auStack_100 [16];
  ushort uStack_f0;
  
  psVar3 = (sbyte *)in_r1r0;
  psVar11 = *(sbyte **)(&UNK_c2da5600 + (int)psVar3 * 4);
  qmi_uim_init_handler();
  puVar6 = &UNK_c3454038;
  psVar4 = psVar11;
  if (psVar11 == (sbyte *)0x0) goto LAB_c0a080c8;
  puVar6 = &UNK_c3454042;
  if (psVar3 == (sbyte *)0x0) goto LAB_c0a080c8;
  qmi_uim_get_request_info();
  sStack_110 = -((int)((ulonglong)in_r1r0 >> 0x20) == 0);
  unaff_r24 = psVar3;
  if (sStack_110 == 0) {
    psVar11[0x31] = 0;
    unaff_r24 = psVar3 + 1;
  }
  if (**(sbyte **)(in_GP + 0x266) != 1) {
    if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
      sVar13 = -1;
    }
    else {
      sVar13 = 0;
    }
    if (sVar13 != 0) goto LAB_c0a078cc;
    if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
      sVar13 = -1;
    }
    else {
      sVar13 = 0;
    }
    if (sVar13 != 0) goto LAB_c0a078cc;
  }
  func_0xc091a618();
  log_4arg();
LAB_c0a078cc:
  sVar13 = psVar11[0x28];
  uVar2 = (char)sVar13 & 0x30;
  if ((sVar13 & '0') == 0) {
    sVar14 = -1;
  }
  else {
    sVar14 = 0;
  }
  if (sVar14 != 0) {
    uVar2 = *(ushort *)(psVar11 + 0x2c);
  }
  if ((((sVar13 & '0') != 0) || (uVar2 != 0xff)) || (psVar11[0xa2c] == 0)) {
    if (psVar11[0x30] == 0) {
      sVar13 = -1;
    }
    else {
      sVar13 = 0;
    }
    if (sVar13 == 0) {
      unaff_r22 = 0;
    }
    uStack_114 = unaff_r22;
    if (psVar11[0x30] != 0) {
LAB_c0a07904:
      puVar12 = *(undefined4 **)(psVar11 + uStack_114 * 0xc + 0x38);
      if (((puVar12 != *(undefined4 **)(psVar3 + 8)) || ((sbyte)in_r1r0 == 0)) ||
         ((*(uint *)(psVar11 + 0x24) & 1) == 0)) {
        func_0xc0a08630(puVar12);
        *(ushort *)(psVar11 + uStack_114 * 0xc + 0x36) =
             *(ushort *)(psVar11 + uStack_114 * 0xc + 0x36) & 0x80;
      }
      func_0xc09bfdb8();
      if (psVar3 == (sbyte *)0x0) {
        sVar13 = -1;
      }
      else {
        sVar13 = 0;
      }
      psVar4 = psVar3;
      if (sVar13 != 0) {
        psVar4 = (sbyte *)puVar12[0x30];
      }
      if (psVar3 == (sbyte *)0x0) {
        func_0xc09c0790();
        if (psVar4 == (sbyte *)0x0) {
          sVar13 = -1;
        }
        else {
          sVar13 = 0;
        }
        psVar5 = psVar4;
        if (sVar13 != 0) {
          psVar5 = (sbyte *)*puVar12;
        }
        if (psVar4 == (sbyte *)0x0) {
          sVar13 = *psVar5;
          if (sVar13 == 0) {
            sVar14 = -1;
          }
          else {
            sVar14 = 0;
          }
          sVar1 = sVar13;
          if (sVar14 == 0) {
            sVar1 = 0;
          }
          if (sVar13 == 0) {
            if ((psVar11[0x29] & '\x04') == 0) {
              sVar13 = -1;
            }
            else {
              sVar13 = 0;
            }
            psVar4 = psVar11;
            unaff_r23 = unaff_r24;
            if ((sVar13 != 0) || (func_0xc0a0c300(puVar12), sVar1 == 0)) {
              qmi_uim_init_handler(0);
              puVar6 = &UNK_c3454812;
              unaff_r19 = psVar11;
              unaff_r24 = psVar11 + uStack_114 * 0xc + 0x34;
              goto LAB_c0a080c8;
            }
            func_0xc0a10ef0(sVar1);
            if ((sVar1 == 0) || (func_0xc0a0c4f0(sVar1), sVar1 == 0)) {
              if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a07a34:
                log_narg();
              }
              else {
                if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
                  sVar13 = -1;
                }
                else {
                  sVar13 = 0;
                }
                if (sVar13 == 0) {
                  if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
                    sVar13 = -1;
                  }
                  else {
                    sVar13 = 0;
                  }
                  if (sVar13 == 0) goto LAB_c0a07a34;
                }
              }
              iVar7 = puVar12[0x36];
              unaff_r20 = (sbyte *)((int)&psRam00000000 + 3);
              unaff_r19 = (sbyte *)((int)&psRam00000000 + 1);
              uVar9 = 1;
              if ((unaff_r24 == (sbyte *)puVar12[0x35]) && ((sbyte *)puVar12[0x35] != (sbyte *)0x0))
              goto LAB_c0a07eb8;
LAB_c0a07ec8:
              unaff_r20 = (sbyte *)((uint)unaff_r20 | 1);
              psStack_12c = (sbyte *)((int)&psRam00000000 + 1);
            }
            else {
              if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a079e8:
                log_2arg(&UNK_c1b68e40);
              }
              else {
                if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
                  sVar13 = -1;
                }
                else {
                  sVar13 = 0;
                }
                if (sVar13 == 0) {
                  if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
                    sVar13 = -1;
                  }
                  else {
                    sVar13 = 0;
                  }
                  if (sVar13 == 0) goto LAB_c0a079e8;
                }
              }
              uVar9 = 0;
              unaff_r20 = (sbyte *)0x0;
              unaff_r19 = (sbyte *)0x0;
              iVar7 = puVar12[0x36];
LAB_c0a07eb8:
              psStack_12c = unaff_r19;
              if (UNK_c2da5604 == 1) goto LAB_c0a07ec8;
            }
            unaff_r27 = (ushort *)0x0;
            if ((uVar9 != 0) && ((uVar9 <= (uint)(iVar7 - (int)unaff_r24) || (iVar7 == 0)))) {
              func_0xc0a08c50();
            }
            qmi_uim_init_handler(0);
            puVar6 = &UNK_c345481c;
            unaff_r26 = (undefined4 *)0x0;
LAB_c0a080c8:
            do {
              psVar11 = unaff_r23;
              msg_send_3(puVar6);
              iVar7 = unaff_r26[0x35];
              func_0xc0a04ef0(psVar3);
              psVar5 = (sbyte *)(iVar7 + (int)psVar3 * (uint)*unaff_r27);
              psVar10 = (sbyte *)((int)&psRam00000000 + 1);
              if (psVar5 != unaff_r24) {
                if (unaff_r20 < psVar5) {
                  sVar13 = -1;
                }
                else {
                  sVar13 = 0;
                }
                if (sVar13 != 0) {
                  psVar10 = psVar4;
                }
                if ((psVar5 <= unaff_r20) && (psVar10 = psVar4, unaff_r24 < psVar5))
                goto LAB_c0a08124;
              }
              do {
                unaff_r19 = unaff_r19 + 1;
                if ((uint)(char)psVar11[0x30] <= ((uint)unaff_r19 & 0xff)) {
                  if ((sbyte)psVar10 == 0) {
                    sVar13 = -1;
                  }
                  else {
                    sVar13 = 0;
                  }
                  if (sVar13 == 0) {
                    psStack_12c = (sbyte *)((int)&psRam00000000 + 1);
                  }
                  goto LAB_c0a08124;
                }
                unaff_r26 = *(undefined4 **)(psVar11 + ((uint)unaff_r19 & 0xff) * 0xc + 0x38);
                func_0xc0a04fe8();
              } while (psVar3 != (sbyte *)((int)&psRam00000000 + 3));
              puVar6 = &UNK_c3454830;
              psVar4 = psVar10;
              unaff_r23 = psVar11;
              if (*(char *)*unaff_r26 < 6) {
                (**(code **)(**(int **)(in_GP + 0xa668) + (uint)*(char *)*unaff_r26 * 4))();
                return;
              }
            } while( true );
          }
          puVar8 = (undefined1 *)0xffffffff;
          func_0xc0a08678(sVar1);
          if (sVar1 == 0) {
            if (*psRam00000000 == 0) {
              func_0xc0a08580();
            }
            else {
              func_0xc0a08580();
            }
          }
          sVar13 = *(sbyte *)*puVar12;
          if (sVar13 == 4) {
            sVar14 = -1;
          }
          else {
            sVar14 = 0;
          }
          sVar1 = sVar13;
          if (sVar14 != 0) {
            puVar8 = &uStack_101;
            sVar1 = 0;
          }
          if (sVar13 == 4) {
            *puVar8 = 0;
            func_0xc09f8260(sVar1);
          }
        }
      }
      goto LAB_c0a082dc;
    }
  }
LAB_c0a082ec:
  if (sStack_110 == 0) {
    psVar11[0x31] = 0;
  }
  return;
LAB_c0a08124:
  func_0xc0a04dc0();
  func_0xc0a08580();
  if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a08158:
    func_0xc0a04dc0();
    log_narg();
    sVar13 = 0x50;
  }
  else {
    sVar13 = (sbyte)**(uint **)(in_GP + 0x4a30);
    if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
      sVar14 = -1;
    }
    else {
      sVar14 = 0;
    }
    if (sVar14 == 0) {
      sVar13 = (sbyte)**(uint **)(in_GP + 0x4a34);
      if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
        sVar14 = -1;
      }
      else {
        sVar14 = 0;
      }
      if (sVar14 == 0) goto LAB_c0a08158;
    }
  }
  if (uStack_114 == 0) {
    sVar14 = -1;
  }
  else {
    sVar14 = 0;
  }
  if (sVar14 != 0) {
    sVar13 = sStack_110;
  }
  unaff_r20 = psStack_130;
  if ((uStack_114 != 0) || (sVar13 != 0)) goto LAB_c0a082dc;
  psVar4 = (sbyte *)((uint)psStack_12c | uStack_11c);
  if (psVar4 == (sbyte *)0x0) {
    sVar13 = -1;
  }
  else {
    sVar13 = 0;
  }
  psVar5 = psVar4;
  if (sVar13 == 0) {
    psVar5 = psVar3;
  }
  if (((psVar4 == (sbyte *)0x0) || (func_0xc0a163b8(psVar5), psVar5 != (sbyte *)0x0)) ||
     (func_0xc0a1814c(), psVar3 != (sbyte *)0x0)) goto LAB_c0a082dc;
  func_0xc07158c0(auStack_100);
  func_0xc091a44c(0);
  uVar9 = uStack_f0 + 6;
  if (4 < uVar9 >> 0xb) {
    uVar9 = uStack_f0 - 0x27fa;
  }
  if ((int)uVar9 < 1) {
    sVar13 = 0;
  }
  else {
    sVar13 = -1;
  }
  if (sVar13 == 0) {
    unaff_r20 = psVar11;
  }
  if (0 < (int)uVar9) goto LAB_c0a082dc;
  if (**(sbyte **)(in_GP + 0x266) == 1) {
LAB_c0a08230:
    log_3arg();
  }
  else {
    if ((**(uint **)(in_GP + 0x4a30) & 4) == 0) {
      sVar13 = -1;
    }
    else {
      sVar13 = 0;
    }
    if (sVar13 == 0) {
      if ((**(uint **)(in_GP + 0x4a34) & 4) == 0) {
        sVar13 = -1;
      }
      else {
        sVar13 = 0;
      }
      if (sVar13 == 0) goto LAB_c0a08230;
    }
  }
  func_0xc0ad9050();
  func_0xc099dfa0();
  func_0xc099dfb0();
  psVar11 = unaff_r20;
LAB_c0a082dc:
  uStack_114 = uStack_114 + 1;
  if ((char)psVar11[0x30] <= uStack_114) goto LAB_c0a082ec;
  goto LAB_c0a07904;
}



======================================================================
[qmi_uim_init_handler] @ 0xC09C2194 (572 bytes)
======================================================================


uint qmi_uim_init_handler(int param_1)

{
  bool bVar1;
  sbyte sVar2;
  int iVar3;
  uint uVar4;
  undefined *puVar5;
  sbyte *psVar6;
  undefined1 *puVar7;
  undefined1 *puVar8;
  undefined4 uVar9;
  sbyte *extraout_r1;
  sbyte *psVar10;
  sbyte *psVar11;
  uint uVar12;
  sbyte *extraout_r1_00;
  sbyte *psVar13;
  sbyte *psVar14;
  sbyte *in_r4;
  undefined4 *unaff_r17;
  sbyte *unaff_r18;
  int in_GP;
  sbyte sVar15;
  sbyte sVar16;
  sbyte sStack_21;
  
  iVar3 = *(int *)(param_1 * 4 + -0x3f8cd45c);
  if (iVar3 != 0) {
    iVar3 = *(int *)(iVar3 + 4);
    uVar4 = 0;
    if (iVar3 != 0) {
      uVar4 = *(uint *)(iVar3 + 0x208);
    }
    return uVar4;
  }
  iVar3 = msg_send_3(&UNK_c344e6ec);
  psVar13 = &sStack_21;
  uVar4 = *(uint *)(iVar3 * 4 + -0x3f8cd45c);
  puVar5 = &UNK_c344e872;
  sStack_21 = 0;
  if (uVar4 != 0) {
    if (extraout_r1 == (sbyte *)0x0) {
      log_4arg();
      goto LAB_c09c23c4;
    }
    psVar10 = *(sbyte **)(uVar4 + 4);
    puVar5 = &UNK_c344e87c;
    if (psVar10 != (sbyte *)0x0) {
      unaff_r17 = *(undefined4 **)(extraout_r1 + 8);
      uVar4 = 0;
      if (unaff_r17 == (undefined4 *)0x0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        uVar4 = (uint)*(char *)((int)unaff_r17 + 0x15);
      }
      if (((unaff_r17 != (undefined4 *)0x0) && (uVar4 != 0)) && (uVar4 < 0x29)) {
        sVar15 = *psVar10;
        if (sVar15 == 0) {
          sVar16 = -1;
        }
        else {
          sVar16 = 0;
        }
        sVar2 = sVar15;
        if (sVar16 == 0) {
          sVar2 = *extraout_r1;
        }
        if (sVar15 != 0) {
          if ((sVar2 & '@') == 0) {
            psVar10 = psVar10 + 0x208;
            psVar11 = (sbyte *)0xffffffff;
            psVar13 = (sbyte *)0x8;
            goto LAB_c09c2240;
          }
          if (**(sbyte **)(in_GP + 0x266) != 1) {
            if ((**(uint **)(in_GP + 0x4a30) & 2) == 0) {
              sVar15 = -1;
            }
            else {
              sVar15 = 0;
            }
            if (sVar15 != 0) goto LAB_c09c23c4;
            if ((**(uint **)(in_GP + 0x4a34) & 2) == 0) {
              sVar15 = -1;
            }
            else {
              sVar15 = 0;
            }
            if (sVar15 != 0) goto LAB_c09c23c4;
          }
          log_3arg(&UNK_c1b666b8,*(undefined2 *)(extraout_r1 + 0x10),unaff_r17[0x31]);
          goto LAB_c09c23c4;
        }
      }
      log_4arg();
      goto LAB_c09c23c4;
    }
  }
  psVar10 = (sbyte *)msg_send_3(puVar5);
  psVar11 = extraout_r1_00;
  do {
    if (in_r4 == extraout_r1) {
      sVar15 = func_0xc10db588(&UNK_c344e886);
      goto LAB_c09c2330;
    }
LAB_c09c2240:
    psVar11 = psVar11 + 1;
    if (psVar11 < psVar13) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      psVar6 = psVar10;
      psVar14 = (sbyte *)(unaff_r17 + 5);
    }
    else {
      psVar6 = psVar10 + 4;
      in_r4 = *(sbyte **)psVar10;
      psVar14 = psVar13;
    }
    bVar1 = psVar11 < psVar13;
    psVar10 = psVar6;
    psVar13 = psVar14;
  } while (bVar1);
  uVar12 = 0xffffffff;
  do {
    psVar13 = psVar14;
    uVar12 = uVar12 + 1;
    if (uVar12 < uVar4) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    psVar14 = psVar13;
    if (sVar15 != 0) {
      psVar14 = psVar13 + 4;
      in_r4 = *(sbyte **)(psVar13 + 4);
    }
    if (uVar4 <= uVar12) goto LAB_c09c2398;
    if (in_r4 == extraout_r1) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 != 0) {
      uVar12 = 2;
    }
  } while (in_r4 != extraout_r1);
  if (uVar12 <= uVar4) {
    *(undefined4 *)(psVar13 + 4) = unaff_r17[uVar4 + 5];
    uVar4 = (uint)*(sbyte *)((int)unaff_r17 + 0x15);
  }
  unaff_r18 = extraout_r1 + 4;
  unaff_r17[(uVar4 & 0xff) + 5] = 0;
  *(sbyte *)((int)unaff_r17 + 0x15) = *(sbyte *)((int)unaff_r17 + 0x15) + -1;
  sVar15 = **(sbyte **)(in_GP + 0x266);
  if (**(sbyte **)(extraout_r1 + 4) == 0) {
    if (sVar15 == 1) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      if ((**(uint **)(in_GP + 0x4a30) & 0x4000) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        if ((**(uint **)(in_GP + 0x4a34) & 0x4000) == 0) {
          sVar15 = -1;
        }
        else {
          sVar15 = 0;
        }
        if (sVar15 == 0) goto LAB_c09c22cc;
      }
    }
    else {
LAB_c09c22cc:
      log_4arg(&UNK_c1b666c0,*(undefined2 *)(extraout_r1 + 0x10));
    }
  }
  else {
LAB_c09c2330:
    if (sVar15 == 1) {
      sVar15 = -1;
    }
    else {
      sVar15 = 0;
    }
    if (sVar15 == 0) {
      if ((**(uint **)(in_GP + 0x4a30) & 0x4000) == 0) {
        sVar15 = -1;
      }
      else {
        sVar15 = 0;
      }
      if (sVar15 == 0) {
        if ((**(uint **)(in_GP + 0x4a34) & 0x4000) == 0) {
          sVar15 = -1;
        }
        else {
          sVar15 = 0;
        }
        if (sVar15 == 0) goto LAB_c09c2350;
      }
    }
    else {
LAB_c09c2350:
      log_4arg();
    }
  }
  func_0xc0b57f98(unaff_r17[0x2e],0,extraout_r1,&sStack_21);
  puVar7 = (undefined1 *)(uint)(char)sStack_21;
  if (puVar7 == (undefined1 *)0x0) {
    sVar15 = -1;
  }
  else {
    sVar15 = 0;
  }
  puVar8 = puVar7;
  if (sVar15 == 0) {
    puVar8 = (undefined1 *)*unaff_r17;
  }
  if (puVar7 != (undefined1 *)0x0) {
    uVar9 = func_0xc09c2b94(*puVar8);
    memset(extraout_r1,0,uVar9);
    if (sStack_21 != 0) goto LAB_c09c23c4;
LAB_c09c2398:
    unaff_r18 = extraout_r1 + 4;
  }
  log_4arg(&UNK_c1b666d0,**(undefined1 **)unaff_r18);
LAB_c09c23c4:
  return (uint)(char)sStack_21;
}



======================================================================
[qmi_uim_pre_dispatch] @ 0xC09C3930 (476 bytes)
======================================================================


int qmi_uim_pre_dispatch(char *param_1,undefined4 param_2,int param_3)

{
  int iVar1;
  char *pcVar2;
  undefined *puVar3;
  char *pcVar4;
  uint uVar5;
  uint *extraout_r1;
  uint uVar6;
  uint uVar7;
  uint uVar8;
  int iVar9;
  uint uVar10;
  sbyte sVar11;
  sbyte sVar12;
  int iVar13;
  
  puVar3 = &UNK_c344e930;
  iVar9 = *(int *)((int)param_1 * 4 + -0x3f8cd45c);
  if (iVar9 != 0) {
    func_0xc0a04c70(param_1);
    iVar1 = qmi_uim_init_handler(param_1);
    puVar3 = &UNK_c344e93a;
    if (iVar1 != 0) {
      func_0xc0a04cc0(param_1,*(undefined4 *)(iVar1 + 8));
      if (*(short *)(*(int *)(iVar1 + 8) + 4) == 0xff) {
        iVar9 = 0xff;
      }
      else {
        pcVar2 = *(char **)(iVar9 + 4);
        puVar3 = &UNK_c344e944;
        if (pcVar2 == (char *)0x0) {
          sVar11 = -1;
        }
        else {
          sVar11 = 0;
        }
        if (sVar11 == 0) {
          puVar3 = (undefined *)(uint)*pcVar2;
        }
        if (pcVar2 == (char *)0x0) goto LAB_c09c3aac;
        if (puVar3 != (undefined *)0x0) {
          uVar10 = 0;
          do {
            pcVar4 = *(char **)(pcVar2 + uVar10 * 4 + 4);
            uVar6 = (uint)*pcVar4;
            if (uVar6 - 1 < 4) {
              uVar6 = 0;
              iVar13 = 0xc;
              if (pcVar4[9] != 0) {
                do {
                  if (*(short *)(*(int *)(pcVar4 + iVar13) + 4) != 0xff) {
                    func_0xc0a04cc0();
                    pcVar2 = *(char **)(iVar9 + 4);
                  }
                  iVar13 = iVar13 + 4;
                  uVar6 = uVar6 + 1;
                  pcVar4 = *(char **)(pcVar2 + uVar10 * 4 + 4);
                } while (uVar6 < pcVar4[9]);
              }
            }
            else if (uVar6 == 5) {
              uVar6 = 0;
              iVar13 = 0xc;
              if (pcVar4[9] != 0) {
                do {
                  if (*(short *)(*(int *)(pcVar4 + iVar13) + 4) != 0xff) {
                    sVar11 = *(sbyte *)(*(int *)(pcVar4 + iVar13) + 0x151);
                    if (sVar11 == 0) {
                      sVar12 = -1;
                    }
                    else {
                      sVar12 = 0;
                    }
                    if (sVar12 == 0) {
                      pcVar2 = param_1;
                    }
                    if (sVar11 != 0) {
                      func_0xc0a04cc0();
                      pcVar2 = *(char **)(iVar9 + 4);
                    }
                  }
                  iVar13 = iVar13 + 4;
                  uVar6 = uVar6 + 1;
                  pcVar4 = *(char **)(pcVar2 + uVar10 * 4 + 4);
                } while (uVar6 < pcVar4[9]);
              }
            }
            else if (uVar6 == 0) {
              uVar6 = 0;
              iVar13 = 0xc;
              if (pcVar4[9] != 0) {
                do {
                  uVar5 = *(uint *)(pcVar4 + iVar13);
                  uVar7 = *(uint *)(iVar1 + 8);
                  if (uVar5 == uVar7) {
                    sVar11 = -1;
                  }
                  else {
                    sVar11 = 0;
                  }
                  uVar8 = uVar7;
                  if (sVar11 == 0) {
                    uVar8 = (uint)*(ushort *)(uVar5 + 4);
                  }
                  if ((uVar5 != uVar7) && (uVar8 != 0xff)) {
                    func_0xc0a04cc0();
                    pcVar2 = *(char **)(iVar9 + 4);
                  }
                  iVar13 = iVar13 + 4;
                  uVar6 = uVar6 + 1;
                  pcVar4 = *(char **)(pcVar2 + uVar10 * 4 + 4);
                } while (uVar6 < pcVar4[9]);
              }
            }
            uVar10 = uVar10 + 1;
          } while (uVar10 < *pcVar2);
        }
        func_0xc0a08320(param_1);
        iVar9 = func_0xc0a04f20(param_1);
      }
      return iVar9;
    }
  }
LAB_c09c3aac:
  uVar10 = msg_send_3(puVar3);
  param_3 = param_3 + -1;
  iVar1 = 0;
  iVar9 = param_3;
  do {
    iVar13 = (iVar9 + iVar1) / 2;
    if (extraout_r1[iVar13] < uVar10) {
      sVar11 = -1;
    }
    else {
      sVar11 = 0;
    }
    if (sVar11 != 0) {
      iVar9 = iVar13 + -1;
    }
    if (uVar10 <= extraout_r1[iVar13]) {
      if (iVar13 == param_3) {
        sVar11 = -1;
      }
      else {
        sVar11 = 0;
      }
      if (sVar11 == 0) {
        iVar1 = iVar13 + 1;
      }
      if ((iVar13 == param_3) || (extraout_r1[iVar1] < uVar10)) break;
    }
  } while (iVar1 <= iVar9);
  if (*extraout_r1 < uVar10) {
    iVar13 = -1;
  }
  return iVar13;
}



======================================================================
[qmi_uim_reset_result] @ 0xC09DBA10 (8 bytes)
======================================================================


undefined * qmi_uim_reset_result(code *param_1)

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



======================================================================
[session_dispatch] @ 0xC071BDE0 (1152 bytes)
======================================================================


int session_dispatch(void)

{
  undefined *puVar1;
  undefined4 uVar2;
  undefined8 in_r1r0;
  int *piVar4;
  ulonglong uVar3;
  uint uVar5;
  code *pcVar6;
  sbyte unaff_r21;
  sbyte sVar7;
  
  piVar4 = (int *)((ulonglong)in_r1r0 >> 0x20);
  puVar1 = &UNK_c34789a8;
  if (((piVar4 != (int *)0x0) && ((int *)*piVar4 != (int *)0x0)) &&
     (puVar1 = &UNK_c34789bc, *(int *)*piVar4 != 0)) {
    func_0xc0719a08(piVar4);
    pcVar6 = *(code **)(*(int *)*piVar4 + 0x20);
    if (pcVar6 == (code *)0x0) {
      sVar7 = -1;
    }
    else {
      sVar7 = 0;
    }
    if (sVar7 == 0) {
      unaff_r21 = -1;
    }
    if (pcVar6 == (code *)0x0) {
      unaff_r21 = -1;
      func_0xc0bdd5ec(&UNK_c1bf4344);
    }
    else {
      (*pcVar6)();
    }
    return (int)unaff_r21;
  }
  panic(puVar1);
  if (puVar1 == (undefined *)0x0) {
    func_0xc071a87c(0,piVar4,&UNK_c1d2e6a0);
    return 0;
  }
  uVar3 = CONCAT44(puVar1,puVar1) & 0xffff0ffffffff;
  uVar5 = (uint)(uVar3 >> 0x20);
  if (uVar5 < 0x80) {
    if ((uVar5 == 0x10) || (uVar5 == 0x20)) {
      qurt_pimutex_unlock(puVar1 + 0x10);
      return (int)uVar3;
    }
    if (uVar5 == 0x40) {
LAB_c071c23c:
      *(undefined4 *)(puVar1 + 8) = *(undefined4 *)(puVar1 + 8);
      func_0xc071638c();
      qurt_thread_set_priority();
      *(undefined4 *)(puVar1 + 8) = 0;
      qurt_pimutex_unlock(puVar1 + 0x10);
      return (int)uVar3;
    }
  }
  else if (uVar5 == 0x80) goto LAB_c071c23c;
  uVar2 = 0;
  func_0xc071a87c((int)uVar3,1,&UNK_c1d2e674);
  return (int)uVar3;
}




Done.
