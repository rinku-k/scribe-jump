defmodule SocialScribeWeb.Chat.ChatComponent do
  use SocialScribeWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "fixed inset-y-0 right-0 z-50 w-full md:w-[400px] bg-white shadow-2xl transform transition-transform duration-300 ease-in-out border-l border-gray-200 flex flex-col font-sans",
        @show && "translate-x-0",
        !@show && "translate-x-full"
      ]}
    >
      <!-- Header -->
      <div class="px-6 py-4 border-b border-gray-100">
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-xl font-semibold text-gray-900 tracking-tight">Ask Anything</h2>
          <button
            phx-click="toggle_chat"
            class="text-gray-400 hover:text-gray-600 transition-colors p-1"
            aria-label="Close chat"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              class="w-5 h-5"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M11.25 4.5l7.5 7.5-7.5 7.5m-6-15l7.5 7.5-7.5 7.5" />
            </svg>
          </button>
        </div>
        
        <div class="flex items-center gap-6 text-sm font-medium border-b border-transparent">
          <button class="text-gray-900 bg-gray-100 px-3 py-1.5 rounded-md">Chat</button>
          <button class="text-gray-500 hover:text-gray-700 transition-colors">History</button>
          <div class="ml-auto">
             <button class="text-gray-400 hover:text-gray-600">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="size-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />
                </svg>
             </button>
          </div>
        </div>
      </div>

      <!-- Messages Area -->
      <div class="flex-1 overflow-y-auto px-6 py-4 space-y-6">
        <!-- Date Separator -->
        <div class="flex items-center justify-center relative">
            <div class="absolute inset-0 flex items-center" aria-hidden="true">
                <div class="w-full border-t border-gray-200"></div>
            </div>
            <div class="relative flex justify-center">
                <span class="bg-white px-3 text-xs text-gray-400">11:17am – November 13, 2025</span>
            </div>
        </div>
        
        <!-- Welcome Message -->
         <div class="text-gray-800 text-[15px] leading-relaxed">
            I can answer questions about Jump meetings and data – just ask!
         </div>

         <!-- User Message -->
         <div class="flex justify-end">
            <div class="bg-gray-100 text-gray-900 px-4 py-3 rounded-2xl rounded-tr-sm text-[15px] leading-relaxed max-w-[90%]">
               Remind me what <img src="https://i.pravatar.cc/150?u=tim" class="w-5 h-5 rounded-full inline-block mx-0.5 align-middle border border-white" alt="Tim"/> <strong>Tim</strong> said about cost considerations
            </div>
         </div>

         <!-- AI Message -->
         <div class="text-gray-800 text-[15px] leading-relaxed space-y-2">
            <p>
                In a meeting on November 3, 2025 <span class="bg-black text-white rounded-full w-5 h-5 inline-flex items-center justify-center text-[10px] mr-0.5">●</span>, 
                <img src="https://i.pravatar.cc/150?u=tim" class="w-5 h-5 rounded-full inline-block mx-0.5 align-middle border border-white" alt="Tim"/> <strong>Tim</strong> mentioned the of cost considerations and explained how to think about packaging, pricing and GTM.
            </p>
            <div class="flex items-center gap-2 mt-2">
                <span class="text-xs text-gray-400">Sources</span>
                <span class="bg-black text-white rounded-full w-4 h-4 inline-flex items-center justify-center text-[8px]">●</span>
            </div>
         </div>
      </div>

      <!-- Input Area -->
      <div class="p-4 border-t border-gray-100 bg-white pb-8">
        <div class="border border-blue-500 rounded-2xl p-3 shadow-sm bg-white relative">
            <button class="flex items-center gap-1.5 text-xs text-gray-500 border border-gray-200 rounded px-2 py-1 hover:bg-gray-50 transition-colors mb-2">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3.5 h-3.5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v6m3-3H9m12 0a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Add context
            </button>
            
            <textarea
                class="w-full text-[15px] text-gray-600 placeholder-gray-400 border-0 focus:ring-0 p-0 resize-none min-h-[60px]"
                placeholder="Ask anything about your meetings"
                rows="2"
            ></textarea>
            
            <div class="flex items-center justify-between mt-2">
                <div class="flex items-center gap-1">
                    <span class="text-xs text-gray-400 mr-1">Sources</span>
                    <div class="flex -space-x-1">
                        <span class="bg-black text-white rounded-full w-4 h-4 inline-flex items-center justify-center text-[8px] z-30 border border-white">●</span>
                         <span class="bg-yellow-500 text-white rounded-full w-4 h-4 inline-flex items-center justify-center text-[8px] z-20 border border-white">G</span>
                          <span class="bg-blue-600 text-white rounded-full w-4 h-4 inline-flex items-center justify-center text-[8px] z-10 border border-white">S</span>
                           <span class="bg-blue-400 text-white rounded-full w-4 h-4 inline-flex items-center justify-center text-[8px] z-0 border border-white">T</span>
                    </div>
                </div>
                <button class="bg-gray-100 hover:bg-gray-200 text-gray-400 hover:text-gray-600 rounded-lg p-1.5 transition-colors">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 10.5 12 3m0 0 7.5 7.5M12 3v18" />
                    </svg>
                </button>
            </div>
        </div>
      </div>
    </div>
    """
  end
end
