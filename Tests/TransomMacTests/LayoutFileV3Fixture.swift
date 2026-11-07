/// A schema-3 layout.json written by hand in the exact shape the 08.1 encoder wrote (sorted keys, pretty printed, World
/// schema 1): display AAAAAAAA-…-0003, Space 3, with H[1 Notes 0.25, 2 Terminal 0.25, Desktop tile 0.5] and the tile
/// hidden (node `"0":{"desktop":{"hidden":true}}`); window 3 floating on screen and window 4 floating at the park rect,
/// with a home frame; a layout set whose desk holds only the visible Desktop tile and floating window 5; and a saved
/// view naming windows 1 and 2. This is the shape every 08.1 user has on disk; it must load and migrate (8.1.1 D-02),
/// never be set aside.
enum LayoutFileV3Fixture {
    static let display = "AAAAAAAA-0000-0000-0000-000000000003"

    static let json = #"""
        {
          "arrangement" : {
            "displayUUIDs" : [
              "AAAAAAAA-0000-0000-0000-000000000003"
            ]
          },
          "homeFrames" : [
            {
              "frame" : {
                "height" : 400,
                "width" : 600,
                "x" : 200,
                "y" : 150
              },
              "window" : {
                "bundleID" : "com.example.editor",
                "pid" : 300,
                "windowID" : 4
              }
            }
          ],
          "layoutSets" : [
            {
              "arrangement" : {
                "displayUUIDs" : [
                  "BBBBBBBB-0000-0000-0000-000000000004"
                ]
              },
              "lastUsed" : 790000000,
              "world" : {
                "desks" : [
                  {
                    "desk" : {
                      "desktop" : {
                        "windows" : [
                          {
                            "frame" : {
                              "height" : 400,
                              "width" : 500,
                              "x" : 100,
                              "y" : 100
                            },
                            "state" : "present",
                            "window" : {
                              "creationOrder" : 0,
                              "identity" : {
                                "bundleID" : "com.example.editor",
                                "pid" : 300,
                                "windowID" : 5
                              },
                              "titleHint" : "Mail"
                            }
                          }
                        ]
                      },
                      "tree" : {
                        "nodes" : {
                          "0" : {
                            "desktop" : {
                              "hidden" : false
                            }
                          }
                        },
                        "root" : 0,
                        "states" : [
        
                        ]
                      }
                    },
                    "key" : {
                      "displayUUID" : "BBBBBBBB-0000-0000-0000-000000000004"
                    }
                  }
                ],
                "ids" : {
                  "next" : 1
                },
                "schemaVersion" : 1
              }
            }
          ],
          "schemaVersion" : 3,
          "session" : {
            "bootSession" : "BOOT-A",
            "cleanExit" : true,
            "launchedAt" : 800000000.25,
            "recoveryLaunch" : false,
            "survivedMinute" : false
          },
          "spaces" : [
            {
              "id" : 3,
              "uuid" : "SPACE-3"
            }
          ],
          "views" : [
            {
              "desk" : {
                "displayUUID" : "AAAAAAAA-0000-0000-0000-000000000003",
                "spaceID" : 3
              },
              "home" : false,
              "slot" : 2,
              "windows" : [
                {
                  "bundleID" : "com.example.editor",
                  "pid" : 300,
                  "windowID" : 1
                },
                {
                  "bundleID" : "com.example.editor",
                  "pid" : 300,
                  "windowID" : 2
                }
              ]
            }
          ],
          "wantedFrames" : [
            {
              "frame" : {
                "height" : 232,
                "width" : 320,
                "x" : 40,
                "y" : 80
              },
              "window" : {
                "bundleID" : "com.example.editor",
                "pid" : 300,
                "windowID" : 1
              }
            }
          ],
          "world" : {
            "desks" : [
              {
                "desk" : {
                  "desktop" : {
                    "windows" : [
                      {
                        "frame" : {
                          "height" : 300,
                          "width" : 400,
                          "x" : 900,
                          "y" : 300
                        },
                        "state" : "present",
                        "window" : {
                          "creationOrder" : 0,
                          "identity" : {
                            "bundleID" : "com.example.editor",
                            "pid" : 300,
                            "windowID" : 3
                          },
                          "titleHint" : "Calendar"
                        }
                      },
                      {
                        "frame" : {
                          "height" : 400,
                          "width" : 600,
                          "x" : 1439,
                          "y" : 899
                        },
                        "state" : "present",
                        "window" : {
                          "creationOrder" : 0,
                          "identity" : {
                            "bundleID" : "com.example.editor",
                            "pid" : 300,
                            "windowID" : 4
                          },
                          "titleHint" : "FileZilla"
                        }
                      }
                    ]
                  },
                  "tree" : {
                    "nodes" : {
                      "0" : {
                        "desktop" : {
                          "hidden" : true
                        }
                      },
                      "1" : {
                        "panel" : {
                          "_0" : {
                            "creationOrder" : 0,
                            "identity" : {
                              "bundleID" : "com.example.editor",
                              "pid" : 300,
                              "windowID" : 1
                            },
                            "titleHint" : "Notes"
                          }
                        }
                      },
                      "2" : {
                        "panel" : {
                          "_0" : {
                            "creationOrder" : 0,
                            "identity" : {
                              "bundleID" : "com.example.editor",
                              "pid" : 300,
                              "windowID" : 2
                            },
                            "titleHint" : "Terminal"
                          }
                        }
                      },
                      "3" : {
                        "split" : {
                          "axis" : "horizontal",
                          "children" : [
                            1,
                            2,
                            0
                          ],
                          "weights" : [
                            0.25,
                            0.25,
                            0.5
                          ]
                        }
                      }
                    },
                    "root" : 3,
                    "states" : [
                      {
                        "state" : "present",
                        "window" : {
                          "bundleID" : "com.example.editor",
                          "pid" : 300,
                          "windowID" : 1
                        }
                      },
                      {
                        "state" : "present",
                        "window" : {
                          "bundleID" : "com.example.editor",
                          "pid" : 300,
                          "windowID" : 2
                        }
                      }
                    ]
                  }
                },
                "key" : {
                  "displayUUID" : "AAAAAAAA-0000-0000-0000-000000000003",
                  "spaceID" : 3
                }
              }
            ],
            "ids" : {
              "next" : 4
            },
            "schemaVersion" : 1
          }
        }
        """#
}
