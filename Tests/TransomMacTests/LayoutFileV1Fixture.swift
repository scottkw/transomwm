/// A schema-1 layout.json exactly as the pre-06-03 encoder wrote it (captured from HEAD 4ccfd9c): desks on Spaces 3
/// and 4 of display AAAAAAAA-…-0001, window 1 docked on Space 3, window 2 floating on Space 4, one home frame and one
/// wanted frame. This is the shape every user has on disk; it must load and migrate, never be set aside.
enum LayoutFileV1Fixture {
    static let display = "AAAAAAAA-0000-0000-0000-000000000001"

    static let json = #"""
        {
          "homeFrames" : [
            {
              "frame" : {
                "height" : 300,
                "width" : 400,
                "x" : 50,
                "y" : 60
              },
              "window" : {
                "bundleID" : "com.example.editor",
                "pid" : 300,
                "windowID" : 2
              }
            }
          ],
          "schemaVersion" : 1,
          "session" : {
            "cleanExit" : true,
            "launchedAt" : 800000000.25,
            "recoveryLaunch" : false,
            "survivedMinute" : false
          },
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
        
                    ]
                  },
                  "tree" : {
                    "nodes" : {
                      "0" : {
                        "desktop" : {
                          "hidden" : false
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
                            "titleHint" : ""
                          }
                        }
                      },
                      "2" : {
                        "split" : {
                          "axis" : "horizontal",
                          "children" : [
                            1,
                            0
                          ],
                          "weights" : [
                            0.5,
                            0.5
                          ]
                        }
                      }
                    },
                    "root" : 2,
                    "states" : [
                      {
                        "state" : "present",
                        "window" : {
                          "bundleID" : "com.example.editor",
                          "pid" : 300,
                          "windowID" : 1
                        }
                      }
                    ]
                  }
                },
                "key" : {
                  "displayUUID" : "AAAAAAAA-0000-0000-0000-000000000001",
                  "spaceID" : 3
                }
              },
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
                            "windowID" : 2
                          },
                          "titleHint" : ""
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
                  "displayUUID" : "AAAAAAAA-0000-0000-0000-000000000001",
                  "spaceID" : 4
                }
              }
            ],
            "ids" : {
              "next" : 3
            },
            "schemaVersion" : 1
          }
        }
        """#
}
