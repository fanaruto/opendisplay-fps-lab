#!/usr/bin/env python3
"""Create a credential-free Shortcuts template; sign with Apple's shortcuts CLI.

The import question is answered locally on the iPad. Never bake a real pairing
address into the file sent to Apple's signing service or into the repository.
"""
import argparse
import plistlib
from pathlib import Path


def token_string(text, output=None):
    value = {"string": text}
    if output:
        value["attachmentsByRange"] = {"{0, 1}": {
            "Type": "ActionOutput", "OutputUUID": output, "OutputName": "结果"
        }}
    return {"WFSerializationType": "WFTextTokenString", "Value": value}


def output_reference(output):
    return {"WFSerializationType": "WFTextTokenAttachment", "Value": {
        "Type": "ActionOutput", "OutputUUID": output, "OutputName": "结果"
    }}


def build():
    clipboard = "B749840D-5DE2-40CB-B776-1A5BC173ACCC"
    download = "89A67F68-C85B-4134-8220-86B6FEC80BA4"
    message = "DA4EC60C-2668-4765-8BF8-E23E23B81A34"
    placeholder = "http://YOUR-MAC.local:43187/PAIRING-KEY/clipboard"
    actions = [
        ("getclipboard", {"UUID": clipboard}),
        ("downloadurl", {
            "UUID": download, "WFURL": placeholder, "WFHTTPMethod": "POST", "WFHTTPBodyType": "JSON",
            "WFJSONValues": {"WFSerializationType": "WFDictionaryFieldValue", "Value": {
                "WFDictionaryFieldValueItems": [{"WFItemType": 0, "WFKey": token_string("text"),
                                                 "WFValue": token_string("\ufffc", clipboard)}]
            }},
        }),
        ("getvalueforkey", {"UUID": message, "WFInput": output_reference(download),
                                "WFDictionaryKey": "message", "WFGetDictionaryValueType": "Value"}),
        ("notification", {"WFNotificationActionTitle": "OpenDisplay 剪贴板",
                          "WFNotificationActionBody": token_string("\ufffc", message),
                          "WFNotificationActionSound": False}),
    ]
    return {
        "WFWorkflowName": "发送剪贴板到 Mac",
        "WFWorkflowActions": [{"WFWorkflowActionIdentifier": "is.workflow.actions." + name,
                               "WFWorkflowActionParameters": params} for name, params in actions],
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4274264319, "WFWorkflowIconGlyphNumber": 59519},
        "WFWorkflowTypes": ["NCWidget"],
        "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFURLContentItem"],
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowImportQuestions": [{"Category": "Parameter", "ActionIndex": 1,
                                      "ParameterKey": "WFURL", "DefaultValue": placeholder,
                                      "Text": "Mac 接收地址：粘贴配对页面中复制的完整地址。"}],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(plistlib.dumps(build(), fmt=plistlib.FMT_XML, sort_keys=False))
