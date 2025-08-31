//
//  ContentView.swift
//  MetalObjViewer
//
//  Created by gzonelee on 9/1/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
#if os(iOS)
        MetalView()
            .ignoresSafeArea()
#else
        MetalViewMacOS()
            .frame(minWidth: 800, minHeight: 600)
#endif
    }
}

#Preview {
    ContentView()
}
